import { useEffect, useState } from 'react'
import { Link, useLocation, useParams } from 'react-router-dom'
import { fetchPublicUser, fetchUserMovies } from '../features/auth/authApi'
import MoviePosterFallback from '../features/movies/MoviePosterFallback'
import { useI18n } from '../i18n/useI18n'

function PublicProfilePage() {
  const { userId } = useParams()
  const location = useLocation()
  const { t } = useI18n()
  const [profile, setProfile] = useState(null)
  const [watchedMovies, setWatchedMovies] = useState([])
  const [watchedMoviesStatus, setWatchedMoviesStatus] = useState('loading')
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true

    async function loadPublicProfile() {
      setIsLoading(true)
      setError('')

      try {
        const [publicUser, moviesData] = await Promise.all([
          fetchPublicUser(userId),
          fetchUserMovies(userId, { page: 1, perPage: 6 }),
        ])

        if (!active) return
        setProfile(publicUser)
        setWatchedMovies(moviesData.movies)
        setWatchedMoviesStatus('ready')
      } catch (err) {
        if (!active) return

        if (err.response?.status === 404) {
          setError(t('publicProfile.notFound'))
        } else {
          setError(t('publicProfile.loadError'))
        }
        setWatchedMoviesStatus('error')
      } finally {
        if (active) {
          setIsLoading(false)
        }
      }
    }

    loadPublicProfile()

    return () => {
      active = false
    }
  }, [t, userId])

  const backTarget = location.state?.from || '/movies'
  const backLabel = location.state?.backLabel || t('publicProfile.backToCatalog')

  if (isLoading) {
    return (
      <section className="mx-auto max-w-3xl py-12">
        <div className="rounded-3xl border border-zinc-800 bg-zinc-900/60 p-8">
          <div className="mx-auto h-28 w-28 animate-pulse rounded-full bg-zinc-800" />
          <div className="mx-auto mt-6 h-8 w-48 animate-pulse rounded bg-zinc-800" />
          <div className="mx-auto mt-3 h-4 w-64 animate-pulse rounded bg-zinc-800/80" />
        </div>
      </section>
    )
  }

  if (error || !profile) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          {t('publicProfile.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          {error || t('publicProfile.notFound')}
        </h1>
        <Link
          className="mt-6 inline-flex rounded-lg bg-red-500 px-5 py-3 text-sm font-semibold text-white transition hover:bg-red-400"
          to={backTarget}
        >
          {backLabel}
        </Link>
      </section>
    )
  }

  const fullName = [profile.firstName, profile.lastName].filter(Boolean).join(' ')

  return (
    <section className="mx-auto max-w-3xl py-12">
      <Link
        className="inline-flex text-sm font-medium text-zinc-400 transition hover:text-white"
        to={backTarget}
      >
        {backLabel}
      </Link>

      <article className="mt-6 overflow-hidden rounded-3xl border border-zinc-800 bg-zinc-900/60">
        <div className="h-32 bg-gradient-to-r from-red-500/30 via-zinc-900 to-zinc-800" />
        <div className="-mt-16 px-6 pb-8 text-center sm:px-10">
          <div className="mx-auto flex h-32 w-32 items-center justify-center overflow-hidden rounded-full border-4 border-zinc-950 bg-zinc-800 text-4xl font-semibold text-white">
            {profile.profilePictureUrl ? (
              <img
                className="h-full w-full object-cover"
                src={profile.profilePictureUrl}
                alt={t('publicProfile.avatarAlt', { username: profile.username })}
              />
            ) : (
              profile.username?.charAt(0).toUpperCase()
            )}
          </div>

          <p className="mt-6 text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {t('publicProfile.label')}
          </p>
          <h1 className="mt-2 text-4xl font-semibold tracking-tight text-white">
            {profile.username}
          </h1>
          {fullName ? (
            <p className="mt-2 text-lg font-medium text-zinc-300">{fullName}</p>
          ) : null}

          <dl className="mt-8 grid gap-3 sm:grid-cols-2">
            <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4 text-left">
              <dt className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
                {t('publicProfile.userId')}
              </dt>
              <dd className="mt-2 text-lg font-semibold text-white">#{profile.id}</dd>
            </div>
            <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4 text-left">
              <dt className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
                {t('publicProfile.preferredLanguage')}
              </dt>
              <dd className="mt-2 text-lg font-semibold text-white">
                {profile.preferredLanguage?.toUpperCase() || t('movieDetails.unknown')}
              </dd>
            </div>
          </dl>
        </div>
      </article>

      <section className="mt-6 rounded-3xl border border-zinc-800 bg-zinc-900/60 p-6">
        <h2 className="text-2xl font-semibold text-white">
          {t('publicProfile.watchedMovies')}
        </h2>

        {watchedMoviesStatus === 'loading' ? (
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            {Array.from({ length: 2 }).map((_, index) => (
              <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4" key={index}>
                <div className="h-5 w-2/3 animate-pulse rounded bg-zinc-800" />
                <div className="mt-3 h-4 w-1/2 animate-pulse rounded bg-zinc-800/80" />
              </div>
            ))}
          </div>
        ) : null}

        {watchedMoviesStatus === 'error' ? (
          <p className="mt-5 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-100">
            {t('publicProfile.watchedMoviesLoadError')}
          </p>
        ) : null}

        {watchedMoviesStatus === 'ready' && watchedMovies.length === 0 ? (
          <p className="mt-5 rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-400">
            {t('publicProfile.noWatchedMovies')}
          </p>
        ) : null}

        {watchedMoviesStatus === 'ready' && watchedMovies.length > 0 ? (
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            {watchedMovies.map((movie) => (
              <Link
                className="group overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 transition hover:-translate-y-1 hover:border-red-400/70"
                key={movie.id}
                to={`/movies/${movie.id}`}
              >
                {movie.coverUrl ? (
                  <img
                    className="h-36 w-full object-cover transition group-hover:scale-105"
                    src={movie.coverUrl}
                    alt={t('movies.card.posterAlt', { title: movie.title })}
                  />
                ) : (
                  <MoviePosterFallback className="h-36" title={movie.title} />
                )}
                <div className="p-4">
                  <h3 className="line-clamp-2 font-semibold text-white">{movie.title}</h3>
                  <p className="mt-2 text-sm text-zinc-400">
                    {movie.year || t('movieDetails.unknown')} · {t('common.imdb')}{' '}
                    {movie.rating || t('movieDetails.notAvailable')}
                  </p>
                </div>
              </Link>
            ))}
          </div>
        ) : null}
      </section>
    </section>
  )
}

export default PublicProfilePage
