import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../features/auth/useAuth'
import Header from './Header'

function AppLayout({ children }) {
  const navigate = useNavigate()
  const { signOut } = useAuth()

  async function handleLogout() {
    await signOut()
    navigate('/login', { replace: true })
  }

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Header onLogout={handleLogout} />
      <main className="mx-auto w-full max-w-7xl px-6 py-8">{children}</main>
    </div>
  )
}

export default AppLayout
