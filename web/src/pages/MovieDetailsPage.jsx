import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { getMovieDetails } from '../features/movies/moviesApi'
import MovieComments from '../features/movies/MovieComments'
import { useI18n } from '../i18n/useI18n'

function MovieDetailsPage() {
  const { movieId } = useParams()
  const { t } = useI18n()
  const [movie, setMovie] = useState(null)
  const [errorId, setErrorId] = useState(null)

  useEffect(() => {
    let active = true

    getMovieDetails(movieId)
      .then((data) => {
        if (!active) {
          return
        }
        setMovie(data)
      })
      .catch(() => {
        if (!active) {
          return
        }
        setErrorId(movieId)
      })

    return () => {
      active = false
    }
  }, [movieId])

  // Derived from state (no synchronous setState in the effect): a movie only
  // counts as ready when the loaded record matches the id in the URL, so a
  // stale movie from a previous id shows the loading state, not wrong data.
  const isError = errorId === movieId
  const isReady = movie != null && String(movie.id) === movieId

  if (!isError && !isReady) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-zinc-500">
          {t('movieDetails.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">{t('common.loading')}</h1>
      </section>
    )
  }

  if (isError) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          {t('movieDetails.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          {t('movieDetails.notFound')}
        </h1>
        <Link
          className="mt-6 inline-flex rounded-lg bg-red-500 px-5 py-3 text-sm font-semibold text-white transition hover:bg-red-400"
          to="/movies"
        >
          {t('movieDetails.backToCatalog')}
        </Link>
      </section>
    )
  }

  const genres = movie.genres?.length
    ? movie.genres.join(' / ')
    : movie.genre || t('movieDetails.unknownGenre')

  return (
    <section className="space-y-10">
      <Link
        className="inline-flex text-sm font-medium text-zinc-400 transition hover:text-white"
        to="/movies"
      >
        {t('movieDetails.backToCatalog')}
      </Link>

      <section className="grid gap-8 lg:grid-cols-[340px_1fr]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900">
          {movie.coverUrl ? (
            <img
              className="h-full w-full object-cover"
              src={movie.coverUrl}
              alt={t('movieDetails.posterAlt', { title: movie.title })}
            />
          ) : (
            <div className="flex aspect-[2/3] items-center justify-center text-sm text-zinc-600">
              {t('movieDetails.noPoster')}
            </div>
          )}
        </div>

        <div className="flex flex-col justify-end">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {genres}
          </p>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight text-white sm:text-6xl">
            {movie.title}
          </h1>
          <div className="mt-5 flex flex-wrap gap-3 text-sm text-zinc-300">
            {movie.year ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.year}</span>
            ) : null}
            {movie.duration ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">
                {t('movieDetails.durationMinutes', { duration: movie.duration })}
              </span>
            ) : null}
            {movie.rating ? (
              <span className="rounded-full bg-amber-400/15 px-3 py-1 font-semibold text-amber-300">
                {t('common.imdb')} {movie.rating}
              </span>
            ) : null}
            <span className="rounded-full bg-zinc-900 px-3 py-1">
              {movie.watched ? t('movieDetails.watched') : t('movieDetails.unwatched')}
            </span>
          </div>
          {movie.summary ? (
            <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-400">
              {movie.summary}
            </p>
          ) : (
            <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-600">
              {t('movieDetails.noSummary')}
            </p>
          )}
        </div>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-black">
          <div className="flex aspect-video items-center justify-center bg-zinc-950">
            <div className="max-w-md px-6 text-center">
              <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
                {t('movieDetails.player')}
              </p>
              <p className="mt-3 text-2xl font-semibold text-white">
                {movie.watched
                  ? t('movieDetails.streamReadyResume')
                  : t('movieDetails.streamReadyPrepare')}
              </p>
              <p className="mt-2 text-sm leading-6 text-zinc-500">
                {t('movieDetails.streamPlaceholder')}
              </p>
            </div>
          </div>
        </div>

        <aside className="space-y-4">
          {movie.genres.length > 0 ? (
            <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
              <h2 className="text-lg font-semibold text-white">{t('movieDetails.genres')}</h2>
              <div className="mt-4 flex flex-wrap gap-2">
                {movie.genres.map((genre) => (
                  <span className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300" key={genre}>
                    {genre}
                  </span>
                ))}
              </div>
            </div>
          ) : null}

          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">{t('movieDetails.subtitles')}</h2>
            {movie.subtitles.length > 0 ? (
              <div className="mt-4 flex flex-wrap gap-2">
                {movie.subtitles.map((subtitle) => (
                  <span className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300" key={subtitle}>
                    {subtitle}
                  </span>
                ))}
              </div>
            ) : (
              <p className="mt-4 text-sm text-zinc-500">{t('movieDetails.noSubtitles')}</p>
            )}
          </div>
        </aside>
      </section>

      <MovieComments
        movieId={movie.id}
        initialCount={movie.commentsCount}
        watched={movie.watched}
      />
    </section>
  )
}

export default MovieDetailsPage
