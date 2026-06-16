import { NavLink } from 'react-router-dom'
import { useI18n } from '../../i18n/useI18n'

function Header({ onLogout }) {
  const { t } = useI18n()
  const linkClass = ({ isActive }) =>
    `rounded-lg px-3 py-2 text-sm font-medium transition ${
      isActive
        ? 'bg-red-500 text-white'
        : 'text-zinc-400 hover:bg-zinc-900 hover:text-white'
    }`

  return (
    <header className="border-b border-zinc-900 bg-zinc-950/95">
      <div className="mx-auto flex w-full max-w-7xl items-center justify-between gap-4 px-6 py-4">
        <NavLink className="text-sm font-semibold uppercase tracking-[0.2em] text-red-400" to="/movies">
          Hypertube
        </NavLink>

        <nav className="flex items-center gap-2">
          <NavLink className={linkClass} to="/movies" end>
            {t('nav.movies')}
          </NavLink>
          <NavLink className={linkClass} to="/profile">
            {t('nav.profile')}
          </NavLink>
        </nav>

        <button
          className="rounded-lg border border-zinc-700 px-4 py-2 text-sm font-medium text-zinc-200 transition hover:border-red-400 hover:text-white"
          type="button"
          onClick={onLogout}
        >
          {t('auth.logout')}
        </button>
      </div>
    </header>
  )
}

export default Header
