import { Link } from 'react-router-dom'
import { useI18n } from '../../i18n/useI18n'

function MovieCard({ movie }) {
  const { t } = useI18n()

  return (
    <Link className="group block overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900/70 transition hover:-translate-y-1 hover:border-red-400/70" to={`/movies/${movie.id}`}>
      <div className="relative aspect-[2/3] overflow-hidden bg-zinc-900">
        {movie.coverUrl ? (
          <img
            className="h-full w-full object-cover transition duration-300 group-hover:scale-105"
            src={movie.coverUrl}
            alt={`Affiche de ${movie.title}`}
            loading="lazy"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-zinc-900 px-6 text-center text-sm font-semibold text-zinc-500">
            {movie.title}
          </div>
        )}
        <span
          className={`absolute left-3 top-3 rounded-full px-3 py-1 text-xs font-semibold ${
            movie.watched
              ? 'bg-emerald-400 text-emerald-950'
              : 'bg-zinc-950/85 text-zinc-200'
          }`}
        >
          {movie.watched ? t('movies.card.seen') : t('movies.card.unseen')}
        </span>
      </div>

      <div className="space-y-3 p-4">
        <div>
          <h2 className="line-clamp-2 text-base font-semibold leading-6 text-white">
            {movie.title}
          </h2>
          <p className="mt-1 text-sm text-zinc-400">
            {movie.year} · {movie.genre}
          </p>
        </div>

        <div className="flex items-center justify-between">
          <span className="rounded-md bg-amber-400/15 px-2 py-1 text-sm font-semibold text-amber-300">
            IMDb {movie.rating}
          </span>
          <span className="rounded-md border border-zinc-700 px-3 py-1.5 text-sm font-medium text-zinc-200 transition group-hover:border-red-400 group-hover:text-white">
            {t('movies.card.view')}
          </span>
        </div>
      </div>
    </Link>
  )
}

export default MovieCard
