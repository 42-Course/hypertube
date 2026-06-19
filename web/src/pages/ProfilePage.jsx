import { useRef, useState } from 'react'
import { updateProfile } from '../features/auth/authApi'
import { useAuth } from '../features/auth/useAuth'
import { useI18n } from '../i18n/useI18n'

// Fallback avatar for accounts without a picture (e.g. password sign-ups).
function fallbackAvatar(user) {
  const name = encodeURIComponent(
    `${user.firstName || ''} ${user.lastName || ''}`.trim() || user.username,
  )
  return `https://ui-avatars.com/api/?name=${name}&background=18181b&color=f87171&size=256`
}

function editableInputClass(isEditing) {
  const baseClass =
    'mt-2 w-full rounded-lg border px-4 py-3 text-sm outline-none transition'

  if (isEditing) {
    return `${baseClass} border-zinc-800 bg-zinc-950 text-white focus:border-red-400`
  }

  return `${baseClass} cursor-not-allowed border-zinc-800 bg-zinc-950/60 text-zinc-500`
}

function EditableLabel({ children, isEditing, onEdit, editLabel }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-sm font-medium text-zinc-300">{children}</span>
      <button
        className="grid h-7 w-7 place-items-center rounded-full border border-red-400/40 bg-red-500/10 text-xs text-red-300 transition hover:border-red-300 hover:text-white disabled:cursor-default disabled:border-zinc-700 disabled:bg-zinc-900 disabled:text-zinc-500"
        type="button"
        aria-label={editLabel}
        disabled={isEditing}
        onClick={onEdit}
      >
        ✎
      </button>
    </div>
  )
}

function ProfilePage() {
  const { language, setLanguage, t } = useI18n()
  const { user, refresh } = useAuth()
  const usernameInputRef = useRef(null)
  const emailInputRef = useRef(null)
  const avatarInputRef = useRef(null)
  const [form, setForm] = useState({
    username: user.username || '',
    email: user.email || '',
    profilePictureUrl: user.profilePictureUrl || '',
  })
  const [avatarPreview, setAvatarPreview] = useState(
    user.profilePictureUrl || fallbackAvatar(user),
  )
  const [editingFields, setEditingFields] = useState({
    username: false,
    email: false,
    profilePictureUrl: false,
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  // History has no API endpoint yet; keep a placeholder list for the layout.
  const watchedMovies = []

  function updateField(name, value) {
    setForm((currentForm) => ({ ...currentForm, [name]: value }))

    if (name === 'profilePictureUrl') {
      setAvatarPreview(value || fallbackAvatar(user))
    }
  }

  function unlockField(name, inputRef) {
    setEditingFields((currentFields) => ({
      ...currentFields,
      [name]: true,
    }))
    window.requestAnimationFrame(() => inputRef.current?.focus())
  }

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    setSuccess('')
    setSubmitting(true)

    try {
      await updateProfile(user.id, form)
      await refresh()
      setEditingFields({
        username: false,
        email: false,
        profilePictureUrl: false,
      })
      setSuccess(t('profile.saveSuccess'))
    } catch (err) {
      const errors = err.response?.data?.errors
      setError(
        Array.isArray(errors)
          ? errors.join(' ')
          : t('profile.saveError'),
      )
    } finally {
      setSubmitting(false)
    }
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
                alt={t('profile.avatarAlt', { username: user.username })}
              />
              <button
                className="absolute bottom-1 right-1 grid h-9 w-9 place-items-center rounded-full border border-red-400/50 bg-zinc-950 text-sm font-semibold text-red-200 transition hover:border-red-300 hover:text-white"
                type="button"
                aria-label={t('profile.changeAvatar')}
                onClick={() => unlockField('profilePictureUrl', avatarInputRef)}
              >
                ✎
              </button>
            </div>
            <p className="mt-3 text-xs text-zinc-500">
              {t('profile.avatarEditableHint')}
            </p>
            <h1 className="mt-5 text-2xl font-semibold text-white">
              {user.firstName} {user.lastName}
            </h1>
            <p className="mt-1 text-sm text-red-400">@{user.username}</p>
            <p className="mt-4 text-sm leading-6 text-zinc-400">
              {t('profile.description')}
            </p>
          </div>

          <div className="mt-6 grid grid-cols-2 gap-3">
            <div className="rounded-xl bg-zinc-950 p-4 text-center">
              <p className="text-2xl font-semibold text-white">
                {watchedMovies.length}
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
                className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
                type="submit"
                form="profile-form"
                disabled={submitting}
              >
                {submitting ? t('profile.saving') : t('profile.save')}
              </button>
            </div>

            {error && (
              <p
                className="mt-6 rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 text-sm text-red-300"
                role="alert"
              >
                {error}
              </p>
            )}

            {success && (
              <p
                className="mt-6 rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-300"
                role="status"
              >
                {success}
              </p>
            )}

            <form id="profile-form" className="mt-6 grid gap-5 md:grid-cols-2" onSubmit={handleSubmit}>
              <label className="block">
                <span className="text-sm font-medium text-zinc-300">{t('profile.firstName')}</span>
                <input
                  className="mt-2 w-full cursor-not-allowed rounded-lg border border-zinc-800 bg-zinc-950/60 px-4 py-3 text-sm text-zinc-500 outline-none"
                  value={user.firstName || ''}
                  type="text"
                  disabled
                />
                <p className="mt-2 text-xs text-zinc-600">{t('profile.notEditable')}</p>
              </label>
              <label className="block">
                <span className="text-sm font-medium text-zinc-300">{t('profile.lastName')}</span>
                <input
                  className="mt-2 w-full cursor-not-allowed rounded-lg border border-zinc-800 bg-zinc-950/60 px-4 py-3 text-sm text-zinc-500 outline-none"
                  value={user.lastName || ''}
                  type="text"
                  disabled
                />
                <p className="mt-2 text-xs text-zinc-600">{t('profile.notEditable')}</p>
              </label>
              <label className="block">
                <EditableLabel
                  editLabel={t('profile.editUsername')}
                  isEditing={editingFields.username}
                  onEdit={() => unlockField('username', usernameInputRef)}
                >
                  {t('profile.username')}
                </EditableLabel>
                <input
                  ref={usernameInputRef}
                  className={editableInputClass(editingFields.username)}
                  value={form.username}
                  onChange={(event) => updateField('username', event.target.value)}
                  readOnly={!editingFields.username}
                  type="text"
                />
              </label>
              <label className="block">
                <EditableLabel
                  editLabel={t('profile.editEmail')}
                  isEditing={editingFields.email}
                  onEdit={() => unlockField('email', emailInputRef)}
                >
                  {t('profile.privateEmail')}
                </EditableLabel>
                <input
                  ref={emailInputRef}
                  className={editableInputClass(editingFields.email)}
                  value={form.email}
                  onChange={(event) => updateField('email', event.target.value)}
                  readOnly={!editingFields.email}
                  type="email"
                />
              </label>
              <label className="block md:col-span-2">
                <EditableLabel
                  editLabel={t('profile.editAvatar')}
                  isEditing={editingFields.profilePictureUrl}
                  onEdit={() => unlockField('profilePictureUrl', avatarInputRef)}
                >
                  {t('profile.avatar')}
                </EditableLabel>
                <input
                  ref={avatarInputRef}
                  className={editableInputClass(editingFields.profilePictureUrl)}
                  value={form.profilePictureUrl}
                  onChange={(event) => updateField('profilePictureUrl', event.target.value)}
                  readOnly={!editingFields.profilePictureUrl}
                  type="url"
                  placeholder={t('profile.avatarPlaceholder')}
                />
                <p className="mt-2 text-sm leading-6 text-zinc-500">
                  {t('profile.avatarUrlHelp')}
                </p>
              </label>
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
                <option value="en">{t('profile.languageOptions.en')}</option>
                <option value="fr">{t('profile.languageOptions.fr')}</option>
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
          {watchedMovies.map((movie) => (
            <article className="rounded-xl border border-zinc-800 bg-zinc-950 p-4" key={movie.id}>
              <h3 className="font-semibold text-white">{movie.title}</h3>
              <p className="mt-2 text-sm text-zinc-400">
                {movie.year} · {t('common.imdb')} {movie.rating}
              </p>
            </article>
          ))}
        </div>
      </section>
    </section>
  )
}

export default ProfilePage
