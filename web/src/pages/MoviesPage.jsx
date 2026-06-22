import { useCallback, useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import MovieCard from '../features/movies/MovieCard'
import MovieFilters from '../features/movies/MovieFilters'
import MovieSearch from '../features/movies/MovieSearch'
import { fetchMovies, searchMovies } from '../features/movies/moviesApi'
import {
  getMovieSource,
  MOVIE_SOURCES,
  saveMovieSource,
} from '../features/settings/settingsStorage'
import { useI18n } from '../i18n/useI18n'

const FIRST_PAGE = 1
const MOVIES_PER_PAGE = 20
const SKELETON_CARD_COUNT = 8
const SEARCH_DEBOUNCE_MS = 800
const SEARCH_PENDING_INDICATOR_MS = 250

function MovieCardSkeleton() {
  return (
    <article className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900/70">
      <div className="aspect-[2/3] animate-pulse bg-zinc-800/70" />
      <div className="space-y-2 p-3 sm:space-y-3 sm:p-4">
        <div className="h-4 w-4/5 animate-pulse rounded bg-zinc-800" />
        <div className="h-3 w-2/5 animate-pulse rounded bg-zinc-800" />
        <div className="flex items-center justify-between pt-1">
          <div className="h-6 w-12 animate-pulse rounded bg-zinc-800 sm:h-7 sm:w-16" />
          <div className="h-7 w-14 animate-pulse rounded bg-zinc-800 sm:h-8 sm:w-20" />
        </div>
      </div>
    </article>
  )
}

function MoviesPage() {
  const { t } = useI18n()
  const [searchParams, setSearchParams] = useSearchParams()
  const searchQueryParam = searchParams.get('query')?.trim() || ''
  // Use the URL `source` param when present so deep links win; otherwise fall
  // back to the persisted per-browser preference (localStorage).
  const sourceFromParam = searchParams.get('source')
  const movieSourceParam =
    sourceFromParam === MOVIE_SOURCES.online
      ? MOVIE_SOURCES.online
      : sourceFromParam === MOVIE_SOURCES.local
        ? MOVIE_SOURCES.local
        : getMovieSource()
  const loadMoreRef = useRef(null)
  const requestIdRef = useRef(0)
  const [searchQuery, setSearchQuery] = useState(searchQueryParam)
  const [submittedSearchQuery, setSubmittedSearchQuery] = useState(searchQueryParam)
  const [filters, setFilters] = useState({
    genre: 'all',
    minYear: 'all',
    maxYear: 'all',
    rating: 'all',
  })
  const [sort, setSort] = useState('popularity')
  const [movies, setMovies] = useState([])
  const [page, setPage] = useState(FIRST_PAGE)
  const [hasMoreMovies, setHasMoreMovies] = useState(true)
  const [isLoading, setIsLoading] = useState(false)
  const [loadingMode, setLoadingMode] = useState(null)
  const [searchSubmitCount, setSearchSubmitCount] = useState(0)
  const [isSearchDebouncing, setIsSearchDebouncing] = useState(false)
  const [searchSource, setSearchSource] = useState('auto')
  const sortLabel = t(`movies.sort.${sort}`)
  const isReplacingMovies = isLoading && loadingMode === 'replace'
  const isAppendingMovies = isLoading && loadingMode === 'append'
  const isManualSearchLoading = isReplacingMovies && searchSource === 'manual'
  const isAutomaticSearchLoading = isReplacingMovies && searchSource !== 'manual'
  const hasPendingSearchQuery = searchQuery.trim() !== submittedSearchQuery.trim()
  const shouldShowReplacingSkeletons = isReplacingMovies || hasPendingSearchQuery
  const activeSearchQuery = submittedSearchQuery.trim()
  const hasSearchQuery = activeSearchQuery.length > 0
  const isLocalSource = movieSourceParam === MOVIE_SOURCES.local
  const pageTitle = isLocalSource ? t('movies.localTitle') : t('movies.onlineTitle')

  const updateSearchParam = useCallback(
    (nextSearchQuery, options = {}) => {
      const nextParams = new URLSearchParams(searchParams)
      const cleanedSearchQuery = nextSearchQuery.trim()

      if (cleanedSearchQuery) {
        nextParams.set('query', cleanedSearchQuery)
      } else {
        nextParams.delete('query')
      }

      setSearchParams(nextParams, { replace: options.replace ?? true })
    },
    [searchParams, setSearchParams],
  )

  const updateSourceParam = useCallback(
    (nextSource) => {
      const nextParams = new URLSearchParams(searchParams)
      nextParams.set('source', nextSource)
      setSearchParams(nextParams, { replace: false })
    },
    [searchParams, setSearchParams],
  )

  const submitSearch = useCallback(
    (nextSearchQuery, options = {}) => {
      const cleanedSearchQuery = nextSearchQuery.trim()

      setSubmittedSearchQuery(cleanedSearchQuery)
      setSearchSubmitCount((currentCount) => currentCount + 1)
      setIsSearchDebouncing(false)
      setSearchSource(options.source || 'manual')
      updateSearchParam(cleanedSearchQuery, options)
    },
    [updateSearchParam],
  )

  const loadMovies = useCallback(
    async ({ nextPage, replace }) => {
      const requestId = requestIdRef.current + 1
      requestIdRef.current = requestId
      setIsLoading(true)
      setLoadingMode(replace ? 'replace' : 'append')

      if (replace) {
        setMovies([])
      }

      try {
        const loadMoviesFromSource = isLocalSource ? fetchMovies : searchMovies
        const result = await loadMoviesFromSource({
          page: nextPage,
          perPage: MOVIES_PER_PAGE,
          query: activeSearchQuery,
          genre: filters.genre,
          minYear: filters.minYear,
          maxYear: filters.maxYear,
          rating: filters.rating,
          sort,
        })

        if (requestId !== requestIdRef.current) {
          return
        }

        setMovies((currentMovies) =>
          replace ? result.movies : [...currentMovies, ...result.movies],
        )
        setPage(result.page)
        setHasMoreMovies(result.hasMore)
      } catch {
        if (requestId !== requestIdRef.current) {
          return
        }

        setMovies((currentMovies) => (replace ? [] : currentMovies))
        setPage(FIRST_PAGE)
        setHasMoreMovies(false)
      } finally {
        if (requestId === requestIdRef.current) {
          setIsLoading(false)
          setLoadingMode(null)
        }
      }
    },
    [
      activeSearchQuery,
      filters.genre,
      filters.maxYear,
      filters.minYear,
      filters.rating,
      isLocalSource,
      sort,
    ],
  )

  useEffect(() => {
    const timerId = window.setTimeout(() => {
      loadMovies({ nextPage: FIRST_PAGE, replace: true })
    }, 0)

    return () => window.clearTimeout(timerId)
  }, [loadMovies, searchSubmitCount])

  useEffect(() => {
    const nextSearchQuery = searchQuery.trim()

    if (nextSearchQuery === submittedSearchQuery.trim()) {
      return undefined
    }

    const pendingTimerId = window.setTimeout(() => {
      setIsSearchDebouncing(true)
    }, SEARCH_PENDING_INDICATOR_MS)

    const searchTimerId = window.setTimeout(() => {
      submitSearch(searchQuery, { replace: true, source: 'auto' })
    }, SEARCH_DEBOUNCE_MS)

    return () => {
      window.clearTimeout(pendingTimerId)
      window.clearTimeout(searchTimerId)
    }
  }, [searchQuery, submittedSearchQuery, submitSearch])

  useEffect(() => {
    if (searchQueryParam === submittedSearchQuery.trim()) {
      return undefined
    }

    const timerId = window.setTimeout(() => {
      setSearchQuery(searchQueryParam)
      setSubmittedSearchQuery(searchQueryParam)
      setSearchSubmitCount((currentCount) => currentCount + 1)
      setIsSearchDebouncing(false)
      setSearchSource('auto')
    }, 0)

    return () => window.clearTimeout(timerId)
  }, [searchQueryParam, submittedSearchQuery])

  function handleSearchChange(nextSearchQuery) {
    setSearchQuery(nextSearchQuery)
    setIsSearchDebouncing(false)
  }

  function handleSearchSubmit() {
    submitSearch(searchQuery, { replace: false, source: 'manual' })
  }

  function handleFiltersChange(nextFilters) {
    setFilters(nextFilters)
  }

  function handleSortChange(nextSort) {
    setSort(nextSort)
  }

  function handleSourceChange(nextSource) {
    setSearchSource('manual')
    setIsSearchDebouncing(false)
    saveMovieSource(nextSource)
    updateSourceParam(nextSource)
  }

  useEffect(() => {
    const loadMoreElement = loadMoreRef.current

    if (!loadMoreElement || !hasMoreMovies || isLoading) {
      return undefined
    }

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          loadMovies({ nextPage: page + 1, replace: false })
        }
      },
      { rootMargin: '200px' },
    )

    observer.observe(loadMoreElement)

    return () => observer.disconnect()
  }, [hasMoreMovies, isLoading, loadMovies, page])

  return (
    <>
      <section className="py-8 sm:py-14">
        <div className="max-w-3xl">
          <div>
            <p className="mb-3 text-sm font-semibold uppercase tracking-[0.18em] text-zinc-500">
              {t('movies.catalog')}
            </p>
            <h1 className="max-w-3xl text-3xl font-semibold tracking-tight text-white sm:text-5xl">
              {t('movies.heroTitle')}
            </h1>
          </div>
        </div>
      </section>

      <section className="space-y-4">
        <div className="grid grid-cols-2 gap-2 rounded-xl border border-zinc-800 bg-zinc-900/60 p-1.5 sm:inline-grid">
          <button
            className={`rounded-lg px-4 py-2 text-sm font-semibold transition ${
              isLocalSource
                ? 'bg-red-500 text-white'
                : 'text-zinc-400 hover:bg-zinc-800 hover:text-white'
            }`}
            type="button"
            onClick={() => handleSourceChange(MOVIE_SOURCES.local)}
          >
            {t('movies.sources.local')}
          </button>
          <button
            className={`rounded-lg px-4 py-2 text-sm font-semibold transition ${
              !isLocalSource
                ? 'bg-red-500 text-white'
                : 'text-zinc-400 hover:bg-zinc-800 hover:text-white'
            }`}
            type="button"
            onClick={() => handleSourceChange(MOVIE_SOURCES.online)}
          >
            {t('movies.sources.online')}
          </button>
        </div>
        <MovieSearch
          isSearchPending={
            isSearchDebouncing ||
            isAutomaticSearchLoading ||
            isManualSearchLoading
          }
          value={searchQuery}
          onChange={handleSearchChange}
          onSubmit={handleSearchSubmit}
        />
        <MovieFilters
          filters={filters}
          onFiltersChange={handleFiltersChange}
          sort={sort}
          onSortChange={handleSortChange}
        />
      </section>

      <section className="py-10">
        <div className="mb-5 flex flex-col justify-between gap-3 sm:flex-row sm:items-end">
          <div>
            <h2 className="text-2xl font-semibold text-white">{pageTitle}</h2>
          </div>
          <p className="text-sm text-zinc-500">
            {t('movies.sort.label')}: {sortLabel}
          </p>
        </div>

        {shouldShowReplacingSkeletons ? (
          <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4">
            {Array.from({ length: SKELETON_CARD_COUNT }, (_, index) => (
              <MovieCardSkeleton key={index} />
            ))}
          </div>
        ) : movies.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 p-10 text-center">
            <h3 className="text-xl font-semibold text-white">
              {hasSearchQuery
                ? t('movies.emptySearchTitle')
                : isLocalSource
                  ? t('movies.emptyCatalogTitle')
                  : t('movies.emptyPopularTitle')}
            </h3>
            <p className="mt-2 text-sm text-zinc-500">
              {hasSearchQuery
                ? t('movies.emptySearchDescription')
                : isLocalSource
                  ? t('movies.emptyCatalogDescription')
                  : t('movies.emptyPopularDescription')}
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4">
            {movies.map((movie) => (
              <MovieCard key={movie.id} movie={movie} />
            ))}
            {isAppendingMovies &&
              Array.from({ length: 4 }, (_, index) => (
                <MovieCardSkeleton key={`append-skeleton-${index}`} />
              ))}
          </div>
        )}

        {hasMoreMovies && !isLoading && (
          <div ref={loadMoreRef} className="mt-8 flex justify-center">
            <div className="rounded-full border border-zinc-800 bg-zinc-900 px-4 py-2 text-sm text-zinc-400">
              {t('movies.loadingMore')}
            </div>
          </div>
        )}
      </section>
    </>
  )
}

export default MoviesPage
