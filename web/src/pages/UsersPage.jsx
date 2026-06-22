import { useEffect, useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { fetchUsers } from '../features/auth/authApi'
import { useI18n } from '../i18n/useI18n'

function UsersPage() {
  const { t } = useI18n()
  const location = useLocation()
  const [users, setUsers] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true

    async function loadUsers() {
      setIsLoading(true)
      setError('')

      try {
        const usersList = await fetchUsers()

        if (!active) return
        setUsers(usersList)
      } catch {
        if (!active) return
        setError(t('users.loadError'))
      } finally {
        if (active) {
          setIsLoading(false)
        }
      }
    }

    loadUsers()

    return () => {
      active = false
    }
  }, [t])

  return (
    <section className="py-10">
      <div className="mb-8 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {t('users.label')}
          </p>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight text-white">
            {t('users.title')}
          </h1>
        </div>
      </div>

      {isLoading && (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 6 }).map((_, index) => (
            <article
              className="rounded-3xl border border-zinc-800 bg-zinc-900/60 p-5"
              key={index}
            >
              <div className="flex items-center gap-4">
                <div className="h-16 w-16 animate-pulse rounded-full bg-zinc-800" />
                <div className="flex-1">
                  <div className="h-5 w-32 animate-pulse rounded bg-zinc-800" />
                  <div className="mt-3 h-4 w-20 animate-pulse rounded bg-zinc-800/80" />
                </div>
              </div>
            </article>
          ))}
        </div>
      )}

      {!isLoading && error && (
        <div className="rounded-3xl border border-red-500/30 bg-red-500/10 p-6 text-sm text-red-100">
          {error}
        </div>
      )}

      {!isLoading && !error && users.length === 0 && (
        <div className="rounded-3xl border border-zinc-800 bg-zinc-900/60 p-8 text-center">
          <h2 className="text-xl font-semibold text-white">{t('users.emptyTitle')}</h2>
          <p className="mt-2 text-sm text-zinc-400">{t('users.emptyDescription')}</p>
        </div>
      )}

      {!isLoading && !error && users.length > 0 && (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {users.map((user) => (
            <article
              className="group rounded-3xl border border-zinc-800 bg-zinc-900/60 p-5 transition hover:-translate-y-1 hover:border-red-400/60 hover:bg-zinc-900"
              key={user.id}
            >
              <div className="flex items-center gap-4">
                <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full bg-gradient-to-br from-red-500/80 to-zinc-800 text-xl font-semibold text-white">
                  {user.profilePictureUrl ? (
                    <img
                      className="h-full w-full object-cover"
                      src={user.profilePictureUrl}
                      alt={t('users.avatarAlt', { username: user.username })}
                    />
                  ) : (
                    user.username?.charAt(0).toUpperCase()
                  )}
                </div>

                <div className="min-w-0 flex-1">
                  <h2 className="truncate text-lg font-semibold text-white">
                    {user.username}
                  </h2>
                </div>
              </div>

              <Link
                className="mt-5 inline-flex w-full items-center justify-center rounded-xl border border-zinc-700 px-4 py-3 text-sm font-semibold text-zinc-100 transition group-hover:border-red-400 group-hover:text-white"
                state={{
                  from: `${location.pathname}${location.search}`,
                  backLabel: t('publicProfile.backToMembers'),
                }}
                to={`/users/${user.id}`}
              >
                {t('users.viewProfile')}
              </Link>
            </article>
          ))}
        </div>
      )}
    </section>
  )
}

export default UsersPage
