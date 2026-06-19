import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { resetPassword } from '../features/auth/authApi'
import { useI18n } from '../i18n/useI18n'

function ResetPasswordPage() {
  const { t } = useI18n()
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token') || ''
  const [password, setPassword] = useState('')
  const [passwordConfirmation, setPasswordConfirmation] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    setSuccess('')

    if (password !== passwordConfirmation) {
      setError(t('auth.resetPassword.mismatch'))
      return
    }

    setSubmitting(true)

    try {
      await resetPassword({
        token,
        password,
        passwordConfirmation,
      })
      setSuccess(t('auth.resetPassword.success'))
      setPassword('')
      setPasswordConfirmation('')
    } catch (err) {
      const errors = err.response?.data?.errors
      setError(
        Array.isArray(errors)
          ? errors.join(' ')
          : t('auth.resetPassword.error'),
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
        <h1 className="text-3xl font-semibold text-white">
          {t('auth.resetPassword.title')}
        </h1>
        <p className="mt-3 text-sm leading-6 text-zinc-400">
          {t('auth.resetPassword.description')}
        </p>

        {!token && (
          <p
            className="mt-6 rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 text-sm text-red-300"
            role="alert"
          >
            {t('auth.resetPassword.invalidToken')}
          </p>
        )}

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
          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.resetPassword.password')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="password"
              type="password"
              autoComplete="new-password"
              minLength={6}
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
              disabled={!token}
            />
          </label>

          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.resetPassword.confirmation')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400 disabled:cursor-not-allowed disabled:opacity-60"
              name="password_confirmation"
              type="password"
              autoComplete="new-password"
              minLength={6}
              value={passwordConfirmation}
              onChange={(event) => setPasswordConfirmation(event.target.value)}
              required
              disabled={!token}
            />
          </label>

          <button
            className="w-full rounded-lg bg-red-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            disabled={submitting || !token}
          >
            {submitting
              ? t('auth.resetPassword.submitting')
              : t('auth.resetPassword.submit')}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-zinc-400">
          {t('auth.resetPassword.newLinkPrompt')}{' '}
          <Link
            className="font-medium text-red-400 hover:text-red-300"
            to="/forgot-password"
          >
            {t('auth.resetPassword.newLink')}
          </Link>
        </p>
      </section>
    </main>
  )
}

export default ResetPasswordPage
