import { useEffect, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import {
  fortyTwoLoginUrl,
  googleLoginUrl,
  login as loginRequest,
} from '../features/auth/authApi'
import { saveAccessToken } from '../features/auth/authStorage'
import { useAuth } from '../features/auth/useAuth'
import { useI18n } from '../i18n/useI18n'

function LoginPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const { isAuthenticated, refresh } = useAuth()
  const { t } = useI18n()

  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [success] = useState(() =>
    searchParams.get('registered') === '1'
      ? t('auth.login.accountCreated')
      : searchParams.get('reset_requested') === '1'
        ? t('auth.login.resetRequested')
        : '',
  )
  const [error, setError] = useState(() => {
    const oauthError = searchParams.get('error')

    if (oauthError === 'oauth_failed') return t('auth.login.oauthFailed')
    if (oauthError === 'oauth_invalid') return t('auth.login.oauthInvalid')

    return ''
  })

  useEffect(() => {
    if (isAuthenticated) {
      navigate('/movies', { replace: true })
    }
  }, [isAuthenticated, navigate])

  async function handleSubmit(event) {
    event.preventDefault()
    setError('')
    setSubmitting(true)

    try {
      const { accessToken } = await loginRequest({
        login: identifier.trim(),
        password,
      })
      saveAccessToken(accessToken)
      await refresh()
      navigate('/movies', { replace: true })
    } catch (err) {
      if (err.response?.status === 401) {
        setError(t('auth.login.invalidCredentials'))
      } else {
        setError(t('auth.login.genericError'))
      }
    } finally {
      setSubmitting(false)
    }
  }

  function handleFortyTwoLogin() {
    window.location.href = fortyTwoLoginUrl()
  }

  function handleGoogleLogin() {
    window.location.href = googleLoginUrl()
  }

  return (
    <main className="min-h-screen bg-zinc-950 px-6 py-10 text-zinc-100">
      <section className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-md flex-col justify-center">
        <p className="mb-3 text-sm font-medium uppercase tracking-[0.2em] text-red-400">
          {t('app.name')}
        </p>
        <h1 className="text-3xl font-semibold text-white">{t('auth.login.title')}</h1>
        <p className="mt-3 text-sm leading-6 text-zinc-400">
          {t('auth.login.description')}
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
          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.login.identifier')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="username"
              type="text"
              autoComplete="username"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              required
            />
          </label>

          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              {t('auth.login.password')}
            </span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </label>

          <div className="text-right">
            <Link
              className="text-sm font-medium text-red-400 transition hover:text-red-300"
              to="/forgot-password"
            >
              {t('auth.forgotPasswordLink')}
            </Link>
          </div>

          <button
            className="w-full rounded-lg bg-red-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            disabled={submitting}
          >
            {submitting ? t('auth.login.submitting') : t('auth.login.submit')}
          </button>
        </form>

        <div className="my-6 flex items-center gap-4">
          <div className="h-px flex-1 bg-zinc-800" />
          <span className="text-xs font-medium uppercase tracking-[0.18em] text-zinc-500">
            {t('auth.login.separator')}
          </span>
          <div className="h-px flex-1 bg-zinc-800" />
        </div>

        <div className="mb-10 space-y-3">
          <button
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-4 py-3 text-sm font-semibold text-white transition hover:border-red-400 hover:bg-zinc-900"
            type="button"
            onClick={handleFortyTwoLogin}
          >
            {t('auth.login.continueWithFortyTwo')}
          </button>

          <button
            className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-4 py-3 text-sm font-semibold text-white transition hover:border-red-400 hover:bg-zinc-900"
            type="button"
            onClick={handleGoogleLogin}
          >
            {t('auth.login.continueWithGoogle')}
          </button>
        </div>

        <p className="mt-6 text-center text-sm text-zinc-400">
          {t('auth.login.registerPrompt')}{' '}
          <Link className="font-medium text-red-400 hover:text-red-300" to="/register">
            {t('auth.login.registerLink')}
          </Link>
        </p>
      </section>
    </main>
  )
}

export default LoginPage
