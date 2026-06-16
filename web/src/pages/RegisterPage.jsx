import { Link } from 'react-router-dom'

function RegisterPage() {
  return (
    <main className="min-h-screen bg-zinc-950 px-6 py-10 text-zinc-100">
      <section className="mx-auto flex min-h-[calc(100vh-5rem)] w-full max-w-md flex-col justify-center">
        <p className="mb-3 text-sm font-medium uppercase tracking-[0.2em] text-red-400">
          Hypertube
        </p>
        <h1 className="text-3xl font-semibold text-white">Inscription</h1>
        <p className="mt-3 text-sm leading-6 text-zinc-400">
          Cree ton compte pour acceder a la bibliotheque de videos.
        </p>

        <form className="mt-8 space-y-5">
          <div className="grid gap-5 sm:grid-cols-2">
            <label className="block">
              <span className="text-sm font-medium text-zinc-200">Prenom</span>
              <input
                className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                name="first_name"
                type="text"
                autoComplete="given-name"
                required
              />
            </label>

            <label className="block">
              <span className="text-sm font-medium text-zinc-200">Nom</span>
              <input
                className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                name="last_name"
                type="text"
                autoComplete="family-name"
                required
              />
            </label>
          </div>

          <label className="block">
            <span className="text-sm font-medium text-zinc-200">Username</span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="username"
              type="text"
              autoComplete="username"
              required
            />
          </label>

          <label className="block">
            <span className="text-sm font-medium text-zinc-200">Email</span>
            <input
              className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
              name="email"
              type="email"
              autoComplete="email"
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
              autoComplete="new-password"
              minLength={6}
              required
            />
          </label>

          <button
            className="w-full rounded-lg bg-red-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-red-400"
            type="submit"
          >
            Creer mon compte
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-zinc-400">
          Deja inscrit ?{' '}
          <Link className="font-medium text-red-400 hover:text-red-300" to="/login">
            Se connecter
          </Link>
        </p>
      </section>
    </main>
  )
}

export default RegisterPage
