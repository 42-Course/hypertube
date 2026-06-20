import { useCallback, useEffect, useRef, useState } from 'react'
import MovieCard from '../features/movies/MovieCard'
import MovieFilters from '../features/movies/MovieFilters'
import MovieSearch from '../features/movies/MovieSearch'
import { searchMovies } from '../features/movies/moviesApi'
import { getMoviesPerPage } from '../features/settings/settingsStorage'
import { useI18n } from '../i18n/useI18n'

const FIRST_PAGE = 1
const SKELETON_CARD_COUNT = 8

function MovieCardSkeleton() {
  return (
    <article className="overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900/70">
      <div className="aspect-[2/3] animate-pulse bg-zinc-800/70" />
      <div className="space-y-3 p-4">
        <div className="h-4 w-4/5 animate-pulse rounded bg-zinc-800" />
        <div className="h-3 w-2/5 animate-pulse rounded bg-zinc-800" />
        <div className="flex items-center justify-between pt-1">
          <div className="h-7 w-16 animate-pulse rounded bg-zinc-800" />
          <div className="h-8 w-20 animate-pulse rounded bg-zinc-800" />
        </div>
      </div>
    </article>
  )
}

function MoviesPage() {
  const { t } = useI18n()
  const loadMoreRef = useRef(null)
  const requestIdRef = useRef(0)
  const [searchQuery, setSearchQuery] = useState('')
  const [submittedSearchQuery, setSubmittedSearchQuery] = useState('')
  const [filters, setFilters] = useState({
    genre: 'all',
    year: 'all',
    rating: 'all',
  })
  const [sort, setSort] = useState('popularity')
  const [movies, setMovies] = useState([])
  const [moviesPerPage] = useState(getMoviesPerPage)
  const [page, setPage] = useState(FIRST_PAGE)
  const [hasMoreMovies, setHasMoreMovies] = useState(true)
  const [isLoading, setIsLoading] = useState(false)
  const [loadingMode, setLoadingMode] = useState(null)
  const [searchSubmitCount, setSearchSubmitCount] = useState(0)
  const sortLabel = t(`movies.sort.${sort}`)
  const isReplacingMovies = isLoading && loadingMode === 'replace'
  const isAppendingMovies = isLoading && loadingMode === 'append'
  const activeSearchQuery = submittedSearchQuery.trim()
  const hasSearchQuery = activeSearchQuery.length > 0

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
        const result = await searchMovies({
          page: nextPage,
          perPage: moviesPerPage,
          query: activeSearchQuery,
          genre: filters.genre,
          year: filters.year,
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
      filters.rating,
      filters.year,
      moviesPerPage,
      sort,
    ],
  )

  useEffect(() => {
    const timerId = window.setTimeout(() => {
      loadMovies({ nextPage: FIRST_PAGE, replace: true })
    }, 0)

    return () => window.clearTimeout(timerId)
  }, [loadMovies, searchSubmitCount])

  function handleSearchChange(nextSearchQuery) {
    setSearchQuery(nextSearchQuery)
  }

  function handleSearchSubmit() {
    setSubmittedSearchQuery(searchQuery)
    setSearchSubmitCount((currentCount) => currentCount + 1)
  }

  function handleFiltersChange(nextFilters) {
    setFilters(nextFilters)
  }

  function handleSortChange(nextSort) {
    setSort(nextSort)
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
      <section className="py-14">
        <div className="max-w-3xl">
          <div>
            <p className="mb-3 text-sm font-semibold uppercase tracking-[0.18em] text-zinc-500">
              {t('movies.catalog')}
            </p>
            <h1 className="max-w-3xl text-4xl font-semibold tracking-tight text-white sm:text-5xl">
              {t('movies.heroTitle')}
            </h1>
          </div>
        </div>
      </section>

      <section className="space-y-4">
        <MovieSearch
          isSearching={isReplacingMovies}
          isDisabled={isReplacingMovies}
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
            <h2 className="text-2xl font-semibold text-white">{t('movies.popular')}</h2>
            <p className="mt-1 text-sm text-zinc-500">
              {t('movies.resultsCount', { count: movies.length })} ·{' '}
              {hasSearchQuery ? t('movies.discoveryNotice') : t('movies.popularNotice')}
            </p>
          </div>
          <p className="text-sm text-zinc-500">
            {t('movies.sort.label')}: {sortLabel}
          </p>
        </div>

        {isReplacingMovies ? (
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {Array.from({ length: SKELETON_CARD_COUNT }, (_, index) => (
              <MovieCardSkeleton key={index} />
            ))}
          </div>
        ) : movies.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 p-10 text-center">
            <h3 className="text-xl font-semibold text-white">
              {hasSearchQuery
                ? t('movies.emptySearchTitle')
                : t('movies.emptyPopularTitle')}
            </h3>
            <p className="mt-2 text-sm text-zinc-500">
              {hasSearchQuery
                ? t('movies.emptySearchDescription')
                : t('movies.emptyPopularDescription')}
            </p>
          </div>
        ) : (
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
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
