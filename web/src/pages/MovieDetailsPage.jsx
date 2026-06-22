import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import HlsPlayer from '../features/movies/HlsPlayer'
import MovieComments from '../features/movies/MovieComments'
import MoviePosterFallback from '../features/movies/MoviePosterFallback'
import { getMovieDetails } from '../features/movies/moviesApi'
import { useMoviePlayback } from '../features/movies/useMoviePlayback'
import { useI18n } from '../i18n/useI18n'

const STREAM_STEPS = ['torrent', 'download', 'stream', 'cache']

function MovieDetailsPage() {
  const { movieId } = useParams()
  const { t } = useI18n()
  const [movie, setMovie] = useState(null)
  const [errorId, setErrorId] = useState(null)
  const [selectedSubtitle, setSelectedSubtitle] = useState('')
  const playback = useMoviePlayback(movieId)

  useEffect(() => {
    let active = true

    getMovieDetails(movieId)
      .then((data) => {
        if (!active) {
          return
        }
        setMovie(data)
        setSelectedSubtitle(data.subtitles?.[0] || '')
        setErrorId(null)
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

  const isPreparing = playback.status === 'preparing' || playback.status === 'buffering'

  return (
    <section className="space-y-7 sm:space-y-10">
      <Link
        className="inline-flex text-sm font-medium text-zinc-400 transition hover:text-white"
        to="/movies"
      >
        {t('movieDetails.backToCatalog')}
      </Link>

      <section className="grid gap-6 lg:grid-cols-[300px_1fr] xl:grid-cols-[340px_1fr]">
        <div className="mx-auto w-full max-w-[220px] overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900 sm:max-w-[280px] lg:max-w-none">
          {movie.coverUrl ? (
            <img
              className="h-full w-full object-cover"
              src={movie.coverUrl}
              alt={t('movieDetails.posterAlt', { title: movie.title })}
            />
          ) : (
            <MoviePosterFallback className="aspect-[2/3]" title={movie.title} />
          )}
        </div>

        <div className="flex flex-col justify-end">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {genres}
          </p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-white sm:text-5xl lg:text-6xl">
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
            <p className="mt-5 max-w-3xl text-sm leading-6 text-zinc-400 sm:text-base sm:leading-7">
              {movie.summary}
            </p>
          ) : (
            <p className="mt-5 max-w-3xl text-sm leading-6 text-zinc-600 sm:text-base sm:leading-7">
              {t('movieDetails.noSummary')}
            </p>
          )}
        </div>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-black">
          {playback.playlistUrl ? (
            <HlsPlayer
              src={playback.playlistUrl}
              authToken={playback.authToken}
              poster={movie.coverUrl}
              onStatus={playback.handlePlayerStatus}
              onError={playback.handlePlayerError}
            />
          ) : (
            <div className="flex aspect-video items-center justify-center bg-[radial-gradient(circle_at_center,_rgba(239,68,68,0.16),_rgba(9,9,11,0.96)_48%,_#000_100%)]">
              <div className="max-w-md px-6 text-center">
                <div className="mx-auto grid h-20 w-20 place-items-center rounded-full border border-red-400/40 bg-red-500/15 text-3xl text-white shadow-[0_0_60px_rgba(239,68,68,0.25)]">
                  ▶
                </div>
                <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
                  {t('movieDetails.player')}
                </p>
                <p className="mt-3 text-2xl font-semibold text-white">
                  {t(`movieDetails.streamStatus.${playback.status}`)}
                </p>
                <p className="mt-2 text-sm leading-6 text-zinc-500">
                  {playback.status === 'error' && playback.errorMessage
                    ? playback.errorMessage
                    : t('movieDetails.streamPlaceholder')}
                </p>
                <button
                  className="mt-6 rounded-xl bg-red-500 px-5 py-3 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-70"
                  type="button"
                  disabled={isPreparing}
                  onClick={playback.start}
                >
                  {isPreparing
                    ? t('movieDetails.preparingPlayback')
                    : t('movieDetails.preparePlayback')}
                </button>
              </div>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3 border-t border-zinc-900 bg-zinc-950 p-3 sm:grid-cols-4 sm:p-4">
            {STREAM_STEPS.map((step, index) => (
              <div className="rounded-xl border border-zinc-800 bg-zinc-900/70 p-3" key={step}>
                <p className="text-xs font-semibold uppercase tracking-[0.16em] text-red-300">
                  {String(index + 1).padStart(2, '0')}
                </p>
                <p className="mt-2 text-sm font-semibold text-white">
                  {t(`movieDetails.streamSteps.${step}.title`)}
                </p>
                <p className="mt-1 text-xs leading-5 text-zinc-500">
                  {t(`movieDetails.streamSteps.${step}.description`)}
                </p>
              </div>
            ))}
          </div>
        </div>

        <aside className="space-y-4">
          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">{t('movieDetails.metadata')}</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('movieDetails.movieId')}</dt>
                <dd className="font-medium text-white">#{movie.id}</dd>
              </div>
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('movieDetails.year')}</dt>
                <dd className="font-medium text-white">
                  {movie.year || t('movieDetails.unknown')}
                </dd>
              </div>
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('movieDetails.length')}</dt>
                <dd className="font-medium text-white">
                  {movie.duration
                    ? t('movieDetails.durationMinutes', { duration: movie.duration })
                    : t('movieDetails.unknownLength')}
                </dd>
              </div>
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('common.imdb')}</dt>
                <dd className="font-medium text-white">
                  {movie.rating || t('movieDetails.notAvailable')}
                </dd>
              </div>
            </dl>
          </div>

          {movie.genres.length > 0 ? (
            <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
              <h2 className="text-lg font-semibold text-white">{t('movieDetails.genres')}</h2>
              <div className="mt-4 flex flex-wrap gap-2">
                {movie.genres.map((genre) => (
                  <span
                    className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300"
                    key={genre}
                  >
                    {genre}
                  </span>
                ))}
              </div>
            </div>
          ) : null}

          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">{t('movieDetails.subtitles')}</h2>
            {movie.subtitles.length > 0 ? (
              <div className="mt-4 space-y-3">
                {selectedSubtitle ? (
                  <p className="text-sm text-zinc-400">
                    {t('movieDetails.selectedSubtitle', { language: selectedSubtitle })}
                  </p>
                ) : null}
                <div className="flex flex-wrap gap-2">
                {movie.subtitles.map((subtitle) => (
                  <button
                    className={`rounded-full px-3 py-1 text-sm transition ${
                      selectedSubtitle === subtitle
                        ? 'bg-red-500 text-white'
                        : 'bg-zinc-950 text-zinc-300 hover:bg-zinc-800 hover:text-white'
                    }`}
                    key={subtitle}
                    type="button"
                    onClick={() => setSelectedSubtitle(subtitle)}
                  >
                    {subtitle}
                  </button>
                ))}
                </div>
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
      />
    </section>
  )
}

export default MovieDetailsPage
