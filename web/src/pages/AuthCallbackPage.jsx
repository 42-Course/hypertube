import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { saveAccessToken } from '../features/auth/authStorage'

function AuthCallbackPage() {
  const navigate = useNavigate()

  useEffect(() => {
    const params = new URLSearchParams(window.location.hash.slice(1))
    const accessToken = params.get('access_token')

    if (!accessToken) {
      navigate('/login?error=oauth_failed', { replace: true })
      return
    }

    saveAccessToken(accessToken)
    navigate('/movies', { replace: true })
  }, [navigate])

  return (
    <main className="grid min-h-screen place-items-center bg-zinc-950 px-6 text-zinc-100">
      <section className="text-center">
        <p className="text-sm font-medium uppercase tracking-[0.2em] text-red-400">
          Hypertube
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          Connexion en cours
        </h1>
        <p className="mt-3 text-sm text-zinc-400">
          Nous finalisons ton authentification.
        </p>
      </section>
    </main>
  )
}

export default AuthCallbackPage
