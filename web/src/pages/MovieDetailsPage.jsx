import { Link, useParams } from 'react-router-dom'
import { getMockMovieDetails } from '../features/movies/mockMovieDetails'

function MovieDetailsPage() {
  const { movieId } = useParams()
  const movie = getMockMovieDetails(movieId)

  if (!movie) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          Movie not found
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          This movie is not in the mock catalog.
        </h1>
        <Link className="mt-6 inline-flex rounded-lg bg-red-500 px-5 py-3 text-sm font-semibold text-white" to="/movies">
          Back to catalog
        </Link>
      </section>
    )
  }

  return (
    <section className="space-y-10">
      <Link className="inline-flex text-sm font-medium text-zinc-400 transition hover:text-white" to="/movies">
        Back to catalog
      </Link>

      <section className="grid gap-8 lg:grid-cols-[340px_1fr]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900">
          <img className="h-full w-full object-cover" src={movie.coverUrl} alt={`Affiche de ${movie.title}`} />
        </div>

        <div className="flex flex-col justify-end">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {movie.genre}
          </p>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight text-white sm:text-6xl">
            {movie.title}
          </h1>
          <div className="mt-5 flex flex-wrap gap-3 text-sm text-zinc-300">
            <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.year}</span>
            <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.length}</span>
            <span className="rounded-full bg-amber-400/15 px-3 py-1 font-semibold text-amber-300">
              IMDb {movie.rating}
            </span>
            <span className="rounded-full bg-zinc-900 px-3 py-1">
              {movie.watched ? 'Watched' : 'Unwatched'}
            </span>
          </div>
          <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-400">
            {movie.summary}
          </p>
        </div>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-black">
          <div className="flex aspect-video items-center justify-center bg-zinc-950">
            <div className="text-center">
              <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
                Player
              </p>
              <p className="mt-3 text-2xl font-semibold text-white">{movie.streamStatus}</p>
              <p className="mt-2 text-sm text-zinc-500">
                The real stream endpoint will replace this placeholder.
              </p>
            </div>
          </div>
        </div>

        <aside className="space-y-4">
          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">Production</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="text-zinc-500">Director</dt>
                <dd className="mt-1 text-zinc-200">{movie.director}</dd>
              </div>
              <div>
                <dt className="text-zinc-500">Producer</dt>
                <dd className="mt-1 text-zinc-200">{movie.producer}</dd>
              </div>
              <div>
                <dt className="text-zinc-500">Main cast</dt>
                <dd className="mt-1 text-zinc-200">{movie.cast.join(', ')}</dd>
              </div>
            </dl>
          </div>

          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">Subtitles</h2>
            <div className="mt-4 flex flex-wrap gap-2">
              {movie.subtitles.map((subtitle) => (
                <span className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300" key={subtitle}>
                  {subtitle}
                </span>
              ))}
            </div>
          </div>
        </aside>
      </section>

      <section className="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-5">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
          <div>
            <h2 className="text-2xl font-semibold text-white">Comments</h2>
            <p className="mt-1 text-sm text-zinc-500">
              Users will be able to discuss the movie here.
            </p>
          </div>
          <button className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400" type="button">
            Add comment
          </button>
        </div>

        <div className="mt-5 space-y-3">
          {movie.comments.length === 0 ? (
            <p className="rounded-xl border border-dashed border-zinc-800 p-5 text-sm text-zinc-500">
              No comments yet.
            </p>
          ) : (
            movie.comments.map((comment) => (
              <article className="rounded-xl border border-zinc-800 bg-zinc-950 p-4" key={comment.id}>
                <div className="flex items-center justify-between gap-3">
                  <p className="font-medium text-white">{comment.author}</p>
                  <time className="text-xs text-zinc-500">{comment.date}</time>
                </div>
                <p className="mt-2 text-sm leading-6 text-zinc-400">{comment.content}</p>
              </article>
            ))
          )}
        </div>
      </section>
    </section>
  )
}

export default MovieDetailsPage
