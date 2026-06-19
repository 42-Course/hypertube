import { useCallback, useEffect, useRef, useState } from 'react'
import MovieCard from '../features/movies/MovieCard'
import MovieFilters from '../features/movies/MovieFilters'
import MovieSearch from '../features/movies/MovieSearch'
import { searchMovies } from '../features/movies/moviesApi'
import { useI18n } from '../i18n/useI18n'

const FIRST_PAGE = 1

function MoviesPage() {
  const { t } = useI18n()
  const loadMoreRef = useRef(null)
  const requestIdRef = useRef(0)
  const [searchQuery, setSearchQuery] = useState('')
  const [filters, setFilters] = useState({
    genre: 'all',
    year: 'all',
    rating: 'all',
  })
  const [sort, setSort] = useState('popularity')
  const [movies, setMovies] = useState([])
  const [page, setPage] = useState(FIRST_PAGE)
  const [hasMoreMovies, setHasMoreMovies] = useState(true)
  const [isLoading, setIsLoading] = useState(false)
  const watchedCount = movies.filter((movie) => movie.watched).length
  const sortLabel = t(`movies.sort.${sort}`)

  const loadMovies = useCallback(
    async ({ nextPage, replace }) => {
      const requestId = requestIdRef.current + 1
      requestIdRef.current = requestId
      setIsLoading(true)

      try {
        const result = await searchMovies({
          page: nextPage,
          query: searchQuery,
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
        setHasMoreMovies(result.movies.length > 0)
      } catch {
        if (requestId !== requestIdRef.current) {
          return
        }

        setPage(FIRST_PAGE)
        setHasMoreMovies(false)
      } finally {
        if (requestId === requestIdRef.current) {
          setIsLoading(false)
        }
      }
    },
    [filters.genre, filters.rating, filters.year, searchQuery, sort],
  )

  useEffect(() => {
    const timerId = window.setTimeout(() => {
      loadMovies({ nextPage: FIRST_PAGE, replace: true })
    }, 0)

    return () => window.clearTimeout(timerId)
  }, [loadMovies])

  function handleSearchChange(nextSearchQuery) {
    setSearchQuery(nextSearchQuery)
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
        <div className="grid gap-10 lg:grid-cols-[1fr_320px] lg:items-end">
          <div>
            <p className="mb-3 text-sm font-semibold uppercase tracking-[0.18em] text-zinc-500">
              {t('movies.catalog')}
            </p>
            <h1 className="max-w-3xl text-4xl font-semibold tracking-tight text-white sm:text-5xl">
              {t('movies.heroTitle')}
            </h1>
            <p className="mt-5 max-w-2xl text-base leading-7 text-zinc-400">
              {t('movies.heroDescription')}
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/70 p-4">
              <p className="text-2xl font-semibold text-white">{movies.length}</p>
              <p className="mt-1 text-sm text-zinc-500">{t('movies.videos')}</p>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-900/70 p-4">
              <p className="text-2xl font-semibold text-white">{watchedCount}</p>
              <p className="mt-1 text-sm text-zinc-500">{t('movies.watched')}</p>
            </div>
          </div>
        </div>
      </section>

      <section className="space-y-4">
        <MovieSearch value={searchQuery} onChange={handleSearchChange} />
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
              {movies.length ? t('movies.noMoviesReturned') : t('movies.apiNotice')}
            </p>
          </div>
          <p className="text-sm text-zinc-500">
            {t('movies.sort.label')}: {sortLabel}
          </p>
        </div>

        {movies.length === 0 && !isLoading ? (
          <div className="rounded-2xl border border-dashed border-zinc-800 bg-zinc-900/40 p-10 text-center">
            <h3 className="text-xl font-semibold text-white">{t('movies.emptyTitle')}</h3>
            <p className="mt-2 text-sm text-zinc-500">{t('movies.emptyDescription')}</p>
          </div>
        ) : (
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {movies.map((movie) => (
              <MovieCard key={movie.id} movie={movie} />
            ))}
          </div>
        )}

        {(hasMoreMovies || isLoading) && (
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
