import { useRef, useState } from 'react'
import { mockProfile } from '../features/profile/mockProfile'
import { useI18n } from '../i18n/useI18n'

function ProfilePage() {
  const { language, setLanguage, t } = useI18n()
  const [avatarPreview, setAvatarPreview] = useState(mockProfile.avatarUrl)
  const fileInputRef = useRef(null)

  function handleAvatarClick() {
    fileInputRef.current?.click()
  }

  function handleAvatarChange(event) {
    const file = event.target.files?.[0]

    if (!file) {
      return
    }

    setAvatarPreview(URL.createObjectURL(file))
  }

  return (
    <section className="space-y-8 py-10">
      <div className="grid gap-6 lg:grid-cols-[360px_1fr]">
        <aside className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-6">
          <div className="flex flex-col items-center text-center">
            <div className="relative">
              <img
                className="h-28 w-28 rounded-full border-4 border-zinc-800 object-cover"
                src={avatarPreview}
                alt={`Avatar de ${mockProfile.username}`}
              />
              <button
                className="absolute bottom-1 right-1 grid h-9 w-9 place-items-center rounded-full border border-zinc-700 bg-zinc-950 text-sm font-semibold text-white transition hover:border-red-400 hover:bg-zinc-900"
                type="button"
                aria-label={t('profile.changeAvatar')}
                onClick={handleAvatarClick}
              >
                ✎
              </button>
              <input
                ref={fileInputRef}
                className="hidden"
                type="file"
                accept="image/png,image/jpeg,image/webp"
                onChange={handleAvatarChange}
              />
            </div>
            <p className="mt-3 text-xs text-zinc-500">
              {t('profile.avatarFormats')}
            </p>
            <h1 className="mt-5 text-2xl font-semibold text-white">
              {mockProfile.firstName} {mockProfile.lastName}
            </h1>
            <p className="mt-1 text-sm text-red-400">@{mockProfile.username}</p>
            <p className="mt-4 text-sm leading-6 text-zinc-400">
              {t('profile.description')}
            </p>
          </div>

          <div className="mt-6 grid grid-cols-2 gap-3">
            <div className="rounded-xl bg-zinc-950 p-4 text-center">
              <p className="text-2xl font-semibold text-white">
                {mockProfile.watchedMovies.length}
              </p>
              <p className="mt-1 text-xs uppercase tracking-[0.16em] text-zinc-500">
                {t('profile.watchedMovies')}
              </p>
            </div>
            <div className="rounded-xl bg-zinc-950 p-4 text-center">
              <p className="text-2xl font-semibold text-white">{language.toUpperCase()}</p>
              <p className="mt-1 text-xs uppercase tracking-[0.16em] text-zinc-500">
                {t('profile.language')}
              </p>
            </div>
          </div>
        </aside>

        <div className="space-y-6">
          <section className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-6">
            <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
                  {t('profile.account')}
                </p>
                <h2 className="mt-2 text-2xl font-semibold text-white">
                  {t('profile.personalInfo')}
                </h2>
              </div>
              <button
                className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400"
                type="button"
              >
                {t('profile.save')}
              </button>
            </div>

            <form className="mt-6 grid gap-5 md:grid-cols-2">
              <label className="block">
                <span className="text-sm font-medium text-zinc-300">{t('profile.firstName')}</span>
                <input
                  className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                  defaultValue={mockProfile.firstName}
                  type="text"
                />
              </label>
              <label className="block">
                <span className="text-sm font-medium text-zinc-300">{t('profile.lastName')}</span>
                <input
                  className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                  defaultValue={mockProfile.lastName}
                  type="text"
                />
              </label>
              <label className="block">
                <span className="text-sm font-medium text-zinc-300">{t('profile.username')}</span>
                <input
                  className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                  defaultValue={mockProfile.username}
                  type="text"
                />
              </label>
              <label className="block">
                <span className="text-sm font-medium text-zinc-300">{t('profile.privateEmail')}</span>
                <input
                  className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                  defaultValue={mockProfile.email}
                  type="email"
                />
              </label>
              <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4 md:col-span-2">
                <p className="text-sm font-medium text-zinc-300">{t('profile.avatar')}</p>
                <p className="mt-2 text-sm leading-6 text-zinc-500">
                  {t('profile.avatarHelp')}
                </p>
              </div>
            </form>
          </section>

          <section className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-6">
            <h2 className="text-2xl font-semibold text-white">{t('profile.preferences')}</h2>
            <p className="mt-2 text-sm text-zinc-400">
              {t('profile.languageHelp')}
            </p>
            <label className="mt-5 block max-w-sm">
              <span className="text-sm font-medium text-zinc-300">{t('profile.preferredLanguage')}</span>
              <select
                className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                value={language}
                onChange={(event) => setLanguage(event.target.value)}
              >
                <option value="en">English</option>
                <option value="fr">Francais</option>
              </select>
            </label>
          </section>
        </div>
      </div>

      <section className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-6">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-end">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
              {t('profile.history')}
            </p>
            <h2 className="mt-2 text-2xl font-semibold text-white">{t('profile.historyTitle')}</h2>
          </div>
          <p className="text-sm text-zinc-500">
            {t('profile.historyVisibility')}
          </p>
        </div>

        <div className="mt-5 grid gap-3 md:grid-cols-3">
          {mockProfile.watchedMovies.map((movie) => (
            <article className="rounded-xl border border-zinc-800 bg-zinc-950 p-4" key={movie.id}>
              <h3 className="font-semibold text-white">{movie.title}</h3>
              <p className="mt-2 text-sm text-zinc-400">
                {movie.year} · IMDb {movie.rating}
              </p>
            </article>
          ))}
        </div>
      </section>
    </section>
  )
}

export default ProfilePage
