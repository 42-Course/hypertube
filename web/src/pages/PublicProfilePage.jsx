import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { fetchPublicUser } from '../features/auth/authApi'
import { useI18n } from '../i18n/useI18n'

function PublicProfilePage() {
  const { userId } = useParams()
  const { t } = useI18n()
  const [profile, setProfile] = useState(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true

    async function loadPublicProfile() {
      setIsLoading(true)
      setError('')

      try {
        const publicUser = await fetchPublicUser(userId)

        if (!active) return
        setProfile(publicUser)
      } catch (err) {
        if (!active) return

        if (err.response?.status === 404) {
          setError(t('publicProfile.notFound'))
        } else {
          setError(t('publicProfile.loadError'))
        }
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
          to="/movies"
        >
          {t('publicProfile.backToCatalog')}
        </Link>
      </section>
    )
  }

  return (
    <section className="mx-auto max-w-3xl py-12">
      <Link
        className="inline-flex text-sm font-medium text-zinc-400 transition hover:text-white"
        to="/movies"
      >
        {t('publicProfile.backToCatalog')}
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

          <dl className="mt-8 grid gap-3 sm:grid-cols-2">
            <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4 text-left">
              <dt className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
                {t('publicProfile.userId')}
              </dt>
              <dd className="mt-2 text-lg font-semibold text-white">#{profile.id}</dd>
            </div>
            <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4 text-left">
              <dt className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
                {t('publicProfile.email')}
              </dt>
              <dd className="mt-2 text-lg font-semibold text-white">
                {t('publicProfile.privateEmail')}
              </dd>
            </div>
          </dl>
        </div>
      </article>
    </section>
  )
}

export default PublicProfilePage
