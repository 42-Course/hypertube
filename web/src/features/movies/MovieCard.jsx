import { Link } from 'react-router-dom'
import { useI18n } from '../../i18n/useI18n'
import MoviePosterFallback from './MoviePosterFallback'

function MovieCard({ movie }) {
  const { t } = useI18n()

  return (
    <Link className="group block overflow-hidden rounded-xl border border-zinc-800 bg-zinc-900/70 transition hover:-translate-y-1 hover:border-red-400/70" to={`/movies/${movie.id}`}>
      <div className="relative aspect-[2/3] overflow-hidden bg-zinc-900">
        {movie.coverUrl ? (
          <img
            className="h-full w-full object-cover transition duration-300 group-hover:scale-105"
            src={movie.coverUrl}
            alt={t('movies.card.posterAlt', { title: movie.title })}
            loading="lazy"
          />
        ) : (
          <MoviePosterFallback title={movie.title} />
        )}
        <span
          className={`absolute left-2 top-2 rounded-full px-2 py-1 text-[10px] font-semibold sm:left-3 sm:top-3 sm:px-3 sm:text-xs ${
            movie.watched
              ? 'bg-emerald-400 text-emerald-950'
              : 'bg-zinc-950/85 text-zinc-200'
          }`}
        >
          {movie.watched ? t('movies.card.seen') : t('movies.card.unseen')}
        </span>
      </div>

      <div className="space-y-2 p-3 sm:space-y-3 sm:p-4">
        <div>
          <h2 className="line-clamp-2 text-sm font-semibold leading-5 text-white sm:text-base sm:leading-6">
            {movie.title}
          </h2>
          <p className="mt-1 text-xs text-zinc-400 sm:text-sm">
            {movie.year} · {movie.genre}
          </p>
        </div>

        <div className="flex items-center justify-between">
          <span className="rounded-md bg-amber-400/15 px-2 py-1 text-xs font-semibold text-amber-300 sm:text-sm">
            {t('common.imdb')} {movie.rating}
          </span>
          <span className="rounded-md border border-zinc-700 px-2 py-1 text-xs font-medium text-zinc-200 transition group-hover:border-red-400 group-hover:text-white sm:px-3 sm:py-1.5 sm:text-sm">
            {t('movies.card.view')}
          </span>
        </div>
      </div>
    </Link>
  )
}

export default MovieCard
