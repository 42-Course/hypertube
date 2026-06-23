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
  const mobileLinkClass = ({ isActive }) =>
    `flex flex-1 items-center justify-center rounded-lg px-1 py-1.5 text-[10px] font-semibold transition ${
      isActive
        ? 'bg-red-500 text-white'
        : 'text-zinc-400 hover:bg-zinc-900 hover:text-white'
    }`

  return (
    <>
      <header className="sticky top-0 z-50 border-b border-zinc-900 bg-zinc-950/85 backdrop-blur">
        <div className="mx-auto flex w-full max-w-7xl items-center justify-between gap-3 px-4 py-3 sm:px-6 sm:py-4">
          <NavLink
            className="text-xs font-semibold uppercase tracking-[0.16em] text-red-400 sm:text-sm sm:tracking-[0.2em]"
            to="/movies"
          >
            {t('app.name')}
          </NavLink>

          <nav className="hidden items-center gap-2 sm:flex">
            <NavLink className={linkClass} to="/movies" end>
              {t('nav.movies')}
            </NavLink>
            <NavLink className={linkClass} to="/users" end>
              {t('nav.users')}
            </NavLink>
            <NavLink className={linkClass} to="/activity" end>
              {t('nav.activity')}
            </NavLink>
            <NavLink className={linkClass} to="/profile">
              {t('nav.profile')}
            </NavLink>
          </nav>

          <button
            className="rounded-lg border border-zinc-700 px-3 py-1.5 text-xs font-medium text-zinc-200 transition hover:border-red-400 hover:text-white sm:px-4 sm:py-2 sm:text-sm"
            type="button"
            onClick={onLogout}
          >
            {t('auth.logout')}
          </button>
        </div>
      </header>

      <nav className="fixed inset-x-0 bottom-0 z-50 grid grid-cols-4 gap-1 border-t border-zinc-900 bg-zinc-950/95 px-1.5 pb-[calc(0.25rem+env(safe-area-inset-bottom))] pt-1.5 backdrop-blur sm:hidden">
        <NavLink className={mobileLinkClass} to="/movies" end>
          {t('nav.movies')}
        </NavLink>
        <NavLink className={mobileLinkClass} to="/users" end>
          {t('nav.users')}
        </NavLink>
        <NavLink className={mobileLinkClass} to="/activity" end>
          {t('nav.activity')}
        </NavLink>
        <NavLink className={mobileLinkClass} to="/profile">
          {t('nav.profile')}
        </NavLink>
      </nav>
    </>
  )
}

export default Header
