import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { fetchUserMovies, updateProfile } from '../features/auth/authApi'
import MoviePosterFallback from '../features/movies/MoviePosterFallback'
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
  const firstNameInputRef = useRef(null)
  const lastNameInputRef = useRef(null)
  const usernameInputRef = useRef(null)
  const emailInputRef = useRef(null)
  const avatarInputRef = useRef(null)
  const passwordInputRef = useRef(null)
  const [form, setForm] = useState({
    firstName: user.firstName || '',
    lastName: user.lastName || '',
    username: user.username || '',
    email: user.email || '',
    preferredLanguage: user.preferredLanguage || language,
    profilePictureUrl: user.profilePictureUrl || '',
  })
  const [avatarFile, setAvatarFile] = useState(null)
  const [passwordForm, setPasswordForm] = useState({
    password: '',
    passwordConfirmation: '',
  })
  const [avatarPreview, setAvatarPreview] = useState(
    user.profilePictureUrl || fallbackAvatar(user),
  )
  const [editingFields, setEditingFields] = useState({
    firstName: false,
    lastName: false,
    username: false,
    email: false,
    password: false,
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [watchedMovies, setWatchedMovies] = useState([])
  const [watchedMoviesStatus, setWatchedMoviesStatus] = useState('loading')

  useEffect(() => {
    let active = true

    async function loadWatchedMovies() {
      setWatchedMoviesStatus('loading')

      try {
        const data = await fetchUserMovies(user.id, { page: 1, perPage: 6 })

        if (!active) return
        setWatchedMovies(data.movies)
        setWatchedMoviesStatus('ready')
      } catch {
        if (!active) return
        setWatchedMoviesStatus('error')
      }
    }

    loadWatchedMovies()

    return () => {
      active = false
    }
  }, [user.id])

  function updateField(name, value) {
    setForm((currentForm) => ({ ...currentForm, [name]: value }))

    if (name === 'profilePictureUrl') {
      setAvatarPreview(value || fallbackAvatar(user))
    }
  }

  function handleAvatarChange(event) {
    const file = event.target.files?.[0]
    if (!file) return

    setAvatarFile(file)
    setAvatarPreview(URL.createObjectURL(file))
  }

  function handlePreferredLanguageChange(value) {
    updateField('preferredLanguage', value)
    setLanguage(value)
  }

  function updatePasswordField(name, value) {
    setPasswordForm((currentForm) => ({ ...currentForm, [name]: value }))
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

    if (
      passwordForm.password ||
      passwordForm.passwordConfirmation
    ) {
      if (passwordForm.password !== passwordForm.passwordConfirmation) {
        setError(t('profile.passwordMismatch'))
        setSubmitting(false)
        return
      }
    }

    try {
      await updateProfile(user.id, {
        ...form,
        password: passwordForm.password,
        avatarFile,
      })
      const updatedUser = await refresh()
      if (updatedUser) {
        setForm({
          firstName: updatedUser.firstName || '',
          lastName: updatedUser.lastName || '',
          username: updatedUser.username || '',
          email: updatedUser.email || '',
          preferredLanguage: updatedUser.preferredLanguage || form.preferredLanguage,
          profilePictureUrl: updatedUser.profilePictureUrl || '',
        })
        setAvatarPreview(updatedUser.profilePictureUrl || fallbackAvatar(updatedUser))
      }
      setEditingFields({
        firstName: false,
        lastName: false,
        username: false,
        email: false,
        password: false,
      })
      setAvatarFile(null)
      setPasswordForm({
        password: '',
        passwordConfirmation: '',
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
    <section className="space-y-6 py-5 sm:space-y-8 sm:py-10">
      <div className="grid items-stretch gap-6 lg:grid-cols-[300px_1fr]">
        <aside className="flex min-h-[520px] flex-col justify-between rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5 lg:min-h-full">
          <div className="flex flex-1 flex-col items-center justify-center text-center">
            <div className="relative">
              <img
                className="h-24 w-24 rounded-full border-4 border-zinc-800 object-cover sm:h-28 sm:w-28"
                src={avatarPreview}
                alt={t('profile.avatarAlt', { username: user.username })}
              />
              <button
                className="absolute bottom-1 right-1 grid h-9 w-9 place-items-center rounded-full border border-red-400/50 bg-zinc-950 text-sm font-semibold text-red-200 transition hover:border-red-300 hover:text-white"
                type="button"
                aria-label={t('profile.changeAvatar')}
                onClick={() => avatarInputRef.current?.click()}
              >
                ✎
              </button>
              <input
                ref={avatarInputRef}
                className="sr-only"
                type="file"
                accept="image/png,image/jpeg,image/webp"
                onChange={handleAvatarChange}
              />
            </div>
            <h1 className="mt-4 text-xl font-semibold text-white sm:mt-5 sm:text-2xl">
              {form.firstName} {form.lastName}
            </h1>
            <p className="mt-1 text-sm text-red-400">@{form.username}</p>
            {avatarFile ? (
              <p className="mt-3 rounded-full bg-zinc-950 px-3 py-1 text-xs text-zinc-400">
                {t('profile.selectedAvatar', { fileName: avatarFile.name })}
              </p>
            ) : null}
          </div>

          <div className="mt-6 grid grid-cols-2 gap-3 border-t border-zinc-800 pt-5">
            <div className="rounded-xl bg-zinc-950 p-3 text-center sm:p-4">
              <p className="text-xl font-semibold text-white sm:text-2xl">
                {watchedMovies.length}
              </p>
              <p className="mt-1 text-xs uppercase tracking-[0.16em] text-zinc-500">
                {t('profile.watchedMovies')}
              </p>
            </div>
            <div className="rounded-xl bg-zinc-950 p-3 text-center sm:p-4">
              <p className="text-xl font-semibold text-white sm:text-2xl">
                {form.preferredLanguage.toUpperCase()}
              </p>
              <p className="mt-1 text-xs uppercase tracking-[0.16em] text-zinc-500">
                {t('profile.language')}
              </p>
            </div>
          </div>

        </aside>

        <div className="space-y-6">
          <section className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5 sm:p-6">
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
                <EditableLabel
                  editLabel={t('profile.editFirstName')}
                  isEditing={editingFields.firstName}
                  onEdit={() => unlockField('firstName', firstNameInputRef)}
                >
                  {t('profile.firstName')}
                </EditableLabel>
                <input
                  ref={firstNameInputRef}
                  className={editableInputClass(editingFields.firstName)}
                  value={form.firstName}
                  onChange={(event) => updateField('firstName', event.target.value)}
                  readOnly={!editingFields.firstName}
                  type="text"
                />
              </label>
              <label className="block">
                <EditableLabel
                  editLabel={t('profile.editLastName')}
                  isEditing={editingFields.lastName}
                  onEdit={() => unlockField('lastName', lastNameInputRef)}
                >
                  {t('profile.lastName')}
                </EditableLabel>
                <input
                  ref={lastNameInputRef}
                  className={editableInputClass(editingFields.lastName)}
                  value={form.lastName}
                  onChange={(event) => updateField('lastName', event.target.value)}
                  readOnly={!editingFields.lastName}
                  type="text"
                />
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
              <div className="md:col-span-2">
                <span className="text-sm font-medium text-zinc-300">
                  {t('profile.preferredLanguage')}
                </span>
                <div className="mt-2 flex flex-wrap gap-2">
                  {['en', 'fr'].map((availableLanguage) => (
                    <button
                      className={`rounded-lg border px-3 py-2 text-left transition ${
                        form.preferredLanguage === availableLanguage
                          ? 'border-red-400 bg-red-500 text-white'
                          : 'border-zinc-800 bg-zinc-950 text-zinc-300 hover:border-zinc-700 hover:text-white'
                      }`}
                      key={availableLanguage}
                      type="button"
                      onClick={() => handlePreferredLanguageChange(availableLanguage)}
                    >
                      <span className="text-sm font-semibold">
                        {t(`profile.languageOptions.${availableLanguage}`)}
                      </span>
                      <span className="ml-2 text-xs uppercase tracking-[0.12em] opacity-70">
                        {availableLanguage}
                      </span>
                    </button>
                  ))}
                </div>
              </div>
              <div className="md:col-span-2">
                <EditableLabel
                  editLabel={t('profile.editPassword')}
                  isEditing={editingFields.password}
                  onEdit={() => unlockField('password', passwordInputRef)}
                >
                  {t('profile.password')}
                </EditableLabel>
                <div className="mt-2 grid gap-4 md:grid-cols-2">
                  <input
                    ref={passwordInputRef}
                    className={editableInputClass(editingFields.password)}
                    value={passwordForm.password}
                    onChange={(event) => updatePasswordField('password', event.target.value)}
                    readOnly={!editingFields.password}
                    type="password"
                    placeholder={t('profile.newPassword')}
                    autoComplete="new-password"
                  />
                  <input
                    className={editableInputClass(editingFields.password)}
                    value={passwordForm.passwordConfirmation}
                    onChange={(event) =>
                      updatePasswordField('passwordConfirmation', event.target.value)
                    }
                    readOnly={!editingFields.password}
                    type="password"
                    placeholder={t('profile.confirmPassword')}
                    autoComplete="new-password"
                  />
                </div>
              </div>
            </form>
          </section>
        </div>
      </div>

      <section className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5 sm:p-6">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-end">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
              {t('profile.history')}
            </p>
            <h2 className="mt-2 text-xl font-semibold text-white sm:text-2xl">{t('profile.historyTitle')}</h2>
          </div>
        </div>

        {watchedMoviesStatus === 'loading' ? (
          <div className="mt-5 grid gap-3 md:grid-cols-3">
            {Array.from({ length: 3 }).map((_, index) => (
              <div className="rounded-xl border border-zinc-800 bg-zinc-950 p-4" key={index}>
                <div className="h-5 w-2/3 animate-pulse rounded bg-zinc-800" />
                <div className="mt-3 h-4 w-1/2 animate-pulse rounded bg-zinc-800/80" />
              </div>
            ))}
          </div>
        ) : null}

        {watchedMoviesStatus === 'error' ? (
          <p className="mt-5 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-100">
            {t('profile.watchedMoviesLoadError')}
          </p>
        ) : null}

        {watchedMoviesStatus === 'ready' && watchedMovies.length === 0 ? (
          <p className="mt-5 rounded-xl border border-zinc-800 bg-zinc-950 p-4 text-sm text-zinc-400">
            {t('profile.noWatchedMovies')}
          </p>
        ) : null}

        {watchedMoviesStatus === 'ready' && watchedMovies.length > 0 ? (
          <div className="mt-5 grid gap-3 md:grid-cols-3">
            {watchedMovies.map((movie) => (
              <Link
                className="group overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 transition hover:-translate-y-1 hover:border-red-400/70"
                key={movie.id}
                to={`/movies/${movie.id}`}
              >
                {movie.coverUrl ? (
                  <img
                    className="h-32 w-full object-cover transition group-hover:scale-105 sm:h-40"
                    src={movie.coverUrl}
                    alt={t('movies.card.posterAlt', { title: movie.title })}
                  />
                ) : (
                  <MoviePosterFallback className="h-32 sm:h-40" title={movie.title} />
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

export default ProfilePage
