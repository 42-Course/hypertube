import { useState } from 'react'
import { Link } from 'react-router-dom'
import { register } from '../features/auth/authApi'
import { useI18n } from '../i18n/useI18n'

function RegisterPage() {
  const { t } = useI18n()
  const [form, setForm] = useState({
    firstName: '',
    lastName: '',
    username: '',
    email: '',
    password: '',
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  function updateField(name, value) {
    setForm((currentForm) => ({ ...currentForm, [name]: value }))
  }

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    setSuccess('')
    setSubmitting(true)

    try {
      await register(form)
      setSuccess(t('auth.register.success'))
      setForm({
        firstName: '',
        lastName: '',
        username: '',
        email: '',
        password: '',
      })
    } catch (err) {
      const errors = err.response?.data?.errors
      setError(
        Array.isArray(errors)
          ? errors.join(' ')
          : t('auth.register.error'),
      )
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <main className="min-h-screen bg-zinc-950 px-6 py-10 text-zinc-100">
      <section className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-md flex-col justify-center">
        <p className="mb-3 text-sm font-medium uppercase tracking-[0.2em] text-red-400">
          {t('app.name')}
        </p>
        <h1 className="text-3xl font-semibold text-white">{t('auth.register.title')}</h1>
        <p className="mt-3 text-sm leading-6 text-zinc-400">
          {t('auth.register.description')}
        </p>

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

        <form className="mt-8 space-y-5" onSubmit={handleSubmit}>
          <div className="grid gap-5 sm:grid-cols-2">
            <label className="block">
              <span className="text-sm font-medium text-zinc-200">
                {t('auth.register.firstName')}
              </span>
              <input
                className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                name="first_name"
                type="text"
                autoComplete="given-name"
                value={form.firstName}
                onChange={(event) => updateField('firstName', event.target.value)}
                required
              />
            </label>

            <label className="block">
              <span className="text-sm font-medium text-zinc-200">
                {t('auth.register.lastName')}
              </span>
              <input
                className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                name="last_name"
                type="text"
                autoComplete="family-name"
                value={form.lastName}
                onChange={(event) => updateField('lastName', event.target.value)}
                required
              />
            </label>
          </div>

          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.register.username')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="username"
              type="text"
              autoComplete="username"
              value={form.username}
              onChange={(event) => updateField('username', event.target.value)}
              required
            />
          </label>

          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.register.email')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="email"
              type="email"
              autoComplete="email"
              value={form.email}
              onChange={(event) => updateField('email', event.target.value)}
              required
            />
          </label>

          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.register.password')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="password"
              type="password"
              autoComplete="new-password"
              minLength={6}
              value={form.password}
              onChange={(event) => updateField('password', event.target.value)}
              required
            />
          </label>

          <button
            className="w-full rounded-lg bg-red-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-red-400"
            type="submit"
            disabled={submitting}
          >
            {submitting ? t('auth.register.submitting') : t('auth.register.submit')}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-zinc-400">
          {t('auth.register.loginPrompt')}{' '}
          <Link className="font-medium text-red-400 hover:text-red-300" to="/login">
            {t('auth.register.loginLink')}
          </Link>
        </p>
      </section>
    </main>
  )
}

export default RegisterPage
