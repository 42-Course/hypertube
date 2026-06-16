import { useEffect, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { fortyTwoLoginUrl, login as loginRequest } from '../features/auth/authApi'
import { saveAccessToken } from '../features/auth/authStorage'
import { useAuth } from '../features/auth/useAuth'

// Errors the 42 OAuth callback can redirect back with (see the Rails
// Users::OmniauthCallbacksController).
const OAUTH_ERRORS = {
  oauth_failed: 'La connexion avec 42 a echoue. Reessaie.',
  oauth_invalid: 'Compte 42 invalide ou non autorise.',
}

function LoginPage() {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const { isAuthenticated, refresh } = useAuth()
  const isDev = import.meta.env.DEV

  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(() => OAUTH_ERRORS[searchParams.get('error')] || '')

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
        setError('Identifiants invalides.')
      } else {
        setError('Une erreur est survenue. Reessaie plus tard.')
      }
    } finally {
      setSubmitting(false)
    }
  }

  function handleFortyTwoLogin() {
    window.location.href = fortyTwoLoginUrl()
  }

  function handleDevLogin() {
    saveAccessToken('dev-token')
    navigate('/movies', { replace: true })
  }

  return (
    <main className="min-h-screen bg-zinc-950 px-6 py-10 text-zinc-100">
      <section className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-md flex-col justify-center">
        <p className="mb-3 text-sm font-medium uppercase tracking-[0.2em] text-red-400">
          Hypertube
        </p>
        <h1 className="text-3xl font-semibold text-white">Connexion</h1>
        <p className="mt-3 text-sm leading-6 text-zinc-400">
          Accede a ton espace pour rechercher, regarder et commenter les videos.
        </p>

        {error && (
          <p
            className="mt-6 rounded-lg border border-red-500/40 bg-red-500/10 px-4 py-3 text-sm text-red-300"
            role="alert"
          >
            {error}
          </p>
        )}

        <form className="mt-8 space-y-5" onSubmit={handleSubmit}>
          <label className="block">
            <span className="text-sm font-medium text-zinc-200">
              Username ou email
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
              Mot de passe
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

          <button
            className="w-full rounded-lg bg-red-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            disabled={submitting}
          >
            {submitting ? 'Connexion...' : 'Se connecter'}
          </button>
        </form>

        <div className="my-6 flex items-center gap-4">
          <div className="h-px flex-1 bg-zinc-800" />
          <span className="text-xs font-medium uppercase tracking-[0.18em] text-zinc-500">
            ou
          </span>
          <div className="h-px flex-1 bg-zinc-800" />
        </div>

        <button
          className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-4 py-3 text-sm font-semibold text-white transition hover:border-red-400 hover:bg-zinc-900"
          type="button"
          onClick={handleFortyTwoLogin}
        >
          Continuer avec 42
        </button>

        {isDev && (
          <button
            className="mt-3 w-full rounded-lg border border-dashed border-zinc-700 px-4 py-3 text-sm font-semibold text-zinc-300 transition hover:border-amber-300 hover:text-white"
            type="button"
            onClick={handleDevLogin}
          >
            Mode dev : entrer sans backend
          </button>
        )}

        <p className="mt-6 text-center text-sm text-zinc-400">
          Pas encore de compte ?{' '}
          <Link className="font-medium text-red-400 hover:text-red-300" to="/register">
            Creer un compte
          </Link>
        </p>
      </section>
    </main>
  )
}

export default LoginPage
