import { Navigate } from 'react-router-dom'
import { useAuth } from '../features/auth/useAuth'

function ProtectedRoute({ children }) {
  const { status } = useAuth()

  // Wait for the initial /me check before deciding, so a valid session is not
  // briefly bounced to /login on a hard refresh.
  if (status === 'loading') {
    return (
      <main className="grid min-h-screen place-items-center bg-zinc-950 text-zinc-400">
        <p className="text-sm">Loading...</p>
      </main>
    )
  }

  if (status !== 'authenticated') {
    return <Navigate to="/login" replace />
  }

  return children
}

export default ProtectedRoute
