import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { requestPasswordReset } from '../features/auth/authApi'
import { useI18n } from '../i18n/useI18n'

function ForgotPasswordPage() {
  const { t } = useI18n()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    setSubmitting(true)

    try {
      await requestPasswordReset(email.trim())
      navigate('/login?reset_requested=1', { replace: true })
    } catch {
      setError(t('auth.forgotPassword.error'))
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
          {t('auth.forgotPassword.title')}
        </h1>
        <p className="mt-3 text-sm leading-6 text-zinc-400">
          {t('auth.forgotPassword.description')}
        </p>

        {error && (
          <p
            className="mt-6 rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 text-sm text-red-300"
            role="alert"
          >
            {error}
          </p>
        )}

        <form className="mt-8 space-y-5 pb-4" onSubmit={handleSubmit}>
          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.forgotPassword.email')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>

          <button
            className="w-full rounded-lg bg-red-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            disabled={submitting}
          >
            {submitting
              ? t('auth.forgotPassword.sending')
              : t('auth.forgotPassword.submit')}
          </button>
        </form>

        <Link
          className="mt-6 text-center text-sm font-medium text-red-400 transition hover:text-red-300"
          to="/login"
        >
          {t('auth.forgotPassword.backToLogin')}
        </Link>
      </section>
    </main>
  )
}

export default ForgotPasswordPage
