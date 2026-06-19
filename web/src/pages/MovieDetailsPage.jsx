import { Link, useParams } from 'react-router-dom'
import { useEffect, useState } from 'react'
import { getMovieDetails } from '../features/movies/moviesApi'

function MovieDetailsPage() {
  const { movieId } = useParams()
  const [movie, setMovie] = useState(null)
  const [errorId, setErrorId] = useState(null)

  useEffect(() => {
    let active = true

    getMovieDetails(movieId)
      .then((data) => {
        if (!active) {
          return
        }
        setMovie(data)
      })
      .catch(() => {
        if (!active) {
          return
        }
        setErrorId(movieId)
      })

    return () => {
      active = false
    }
  }, [movieId])

  // Derived from state (no synchronous setState in the effect): a movie only
  // counts as ready when the loaded record matches the id in the URL, so a
  // stale movie from a previous id shows the loading state, not wrong data.
  const isError = errorId === movieId
  const isReady = movie != null && String(movie.id) === movieId

  if (!isError && !isReady) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-zinc-500">
          Loading
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">Loading movie…</h1>
      </section>
    )
  }

  if (isError) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          Movie not found
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          Sorry we couldn't find this movie.
        </h1>
        <Link
          className="mt-6 inline-flex rounded-lg bg-red-500 px-5 py-3 text-sm font-semibold text-white transition hover:bg-red-400"
          to="/movies"
        >
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
          {movie.coverUrl ? (
            <img className="h-full w-full object-cover" src={movie.coverUrl} alt={`Poster for ${movie.title}`} />
          ) : (
            <div className="flex aspect-[2/3] items-center justify-center text-sm text-zinc-600">
              No poster
            </div>
          )}
        </div>

        <div className="flex flex-col justify-end">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {movie.genre}
          </p>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight text-white sm:text-6xl">
            {movie.title}
          </h1>
          <div className="mt-5 flex flex-wrap gap-3 text-sm text-zinc-300">
            {movie.year ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.year}</span>
            ) : null}
            {movie.duration ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.duration} min</span>
            ) : null}
            {movie.rating ? (
              <span className="rounded-full bg-amber-400/15 px-3 py-1 font-semibold text-amber-300">
                IMDb {movie.rating}
              </span>
            ) : null}
            <span className="rounded-full bg-zinc-900 px-3 py-1">
              {movie.watched ? 'Watched' : 'Unwatched'}
            </span>
          </div>
          {movie.summary ? (
            <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-400">
              {movie.summary}
            </p>
          ) : (
            <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-600">
              No summary available yet.
            </p>
          )}
        </div>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-black">
          <div className="flex aspect-video items-center justify-center bg-zinc-950">
            <div className="text-center">
              <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
                Player
              </p>
              <p className="mt-3 text-2xl font-semibold text-white">Stream coming soon</p>
              <p className="mt-2 text-sm text-zinc-500">
                The real stream endpoint will replace this placeholder.
              </p>
            </div>
          </div>
        </div>

        <aside className="space-y-4">
          {movie.genres.length > 0 ? (
            <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
              <h2 className="text-lg font-semibold text-white">Genres</h2>
              <div className="mt-4 flex flex-wrap gap-2">
                {movie.genres.map((genre) => (
                  <span className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300" key={genre}>
                    {genre}
                  </span>
                ))}
              </div>
            </div>
          ) : null}

          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">Subtitles</h2>
            {movie.subtitles.length > 0 ? (
              <div className="mt-4 flex flex-wrap gap-2">
                {movie.subtitles.map((subtitle) => (
                  <span className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300" key={subtitle}>
                    {subtitle}
                  </span>
                ))}
              </div>
            ) : (
              <p className="mt-4 text-sm text-zinc-500">No subtitles available yet.</p>
            )}
          </div>
        </aside>
      </section>

      <section className="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-5">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
          <div>
            <h2 className="text-2xl font-semibold text-white">
              Comments
              <span className="ml-2 text-base font-normal text-zinc-500">({movie.commentsCount})</span>
            </h2>
            <p className="mt-1 text-sm text-zinc-500">
              Users will be able to discuss the movie here.
            </p>
          </div>
          <button className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400" type="button">
            Add comment
          </button>
        </div>

        <div className="mt-5">
          <p className="rounded-xl border border-dashed border-zinc-800 p-5 text-sm text-zinc-500">
            {movie.commentsCount === 0
              ? 'No comments yet.'
              : 'Comments will appear here once the discussion endpoint is wired up.'}
          </p>
        </div>
      </section>
    </section>
  )
}

export default MovieDetailsPage
