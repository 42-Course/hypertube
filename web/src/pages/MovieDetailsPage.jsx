import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import {
  createMovieComment,
  fetchMovieComments,
  fetchMovieDetails,
} from '../features/movies/moviesApi'
import { useI18n } from '../i18n/useI18n'

function formatCommentDate(date, language) {
  if (!date) return ''

  return new Intl.DateTimeFormat(language === 'fr' ? 'fr-FR' : 'en-US', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(new Date(date))
}

function MovieDetailsPage() {
  const { movieId } = useParams()
  const { language, t } = useI18n()
  const [movie, setMovie] = useState(null)
  const [comments, setComments] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [isPostingComment, setIsPostingComment] = useState(false)
  const [error, setError] = useState('')
  const [commentError, setCommentError] = useState('')
  const [commentContent, setCommentContent] = useState('')

  const loadMovie = useCallback(async () => {
    setIsLoading(true)
    setError('')

    try {
      const [movieResult, commentsResult] = await Promise.all([
        fetchMovieDetails(movieId),
        fetchMovieComments(movieId),
      ])

      setMovie(movieResult)
      setComments(commentsResult.comments)
    } catch (err) {
      if (err.response?.status === 404) {
        setError(t('movieDetails.notFound'))
      } else {
        setError(t('movieDetails.loadError'))
      }
    } finally {
      setIsLoading(false)
    }
  }, [movieId, t])

  useEffect(() => {
    const timerId = window.setTimeout(loadMovie, 0)

    return () => window.clearTimeout(timerId)
  }, [loadMovie])

  async function handleCommentSubmit(event) {
    event.preventDefault()

    if (!commentContent.trim() || !movie?.watched) {
      return
    }

    setIsPostingComment(true)
    setCommentError('')

    try {
      await createMovieComment(movie.id, commentContent.trim())
      const commentsResult = await fetchMovieComments(movie.id)

      setComments(commentsResult.comments)
      setMovie((currentMovie) => ({
        ...currentMovie,
        commentsCount: commentsResult.total,
      }))
      setCommentContent('')
    } catch {
      setCommentError(t('movieDetails.publishError'))
    } finally {
      setIsPostingComment(false)
    }
  }

  if (isLoading) {
    return (
      <section className="space-y-8 py-10">
        <div className="h-5 w-32 animate-pulse rounded bg-zinc-800" />
        <div className="grid gap-8 lg:grid-cols-[340px_1fr]">
          <div className="aspect-[2/3] animate-pulse rounded-2xl bg-zinc-900" />
          <div className="space-y-4 self-end">
            <div className="h-4 w-40 animate-pulse rounded bg-zinc-800" />
            <div className="h-16 max-w-2xl animate-pulse rounded bg-zinc-800" />
            <div className="h-24 max-w-3xl animate-pulse rounded bg-zinc-900" />
          </div>
        </div>
      </section>
    )
  }

  if (error || !movie) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          {t('movieDetails.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          {error || t('movieDetails.notFound')}
        </h1>
        <Link
          className="mt-6 inline-flex rounded-lg bg-red-500 px-5 py-3 text-sm font-semibold text-white"
          to="/movies"
        >
          {t('movieDetails.backToCatalog')}
        </Link>
      </section>
    )
  }

  const genres = movie.genres?.length
    ? movie.genres.join(' / ')
    : movie.genre || t('movieDetails.unknownGenre')

  return (
    <section className="space-y-10">
      <Link
        className="inline-flex text-sm font-medium text-zinc-400 transition hover:text-white"
        to="/movies"
      >
        {t('movieDetails.backToCatalog')}
      </Link>

      <section className="grid gap-8 lg:grid-cols-[340px_1fr]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900">
          {movie.coverUrl ? (
            <img
              className="h-full w-full object-cover"
              src={movie.coverUrl}
              alt={t('movieDetails.posterAlt', { title: movie.title })}
            />
          ) : (
            <div className="flex aspect-[2/3] items-center justify-center p-8 text-center text-sm text-zinc-500">
              {t('movieDetails.noPoster')}
            </div>
          )}
        </div>

        <div className="flex flex-col justify-end">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {genres}
          </p>
          <h1 className="mt-3 text-4xl font-semibold tracking-tight text-white sm:text-6xl">
            {movie.title}
          </h1>
          <div className="mt-5 flex flex-wrap gap-3 text-sm text-zinc-300">
            <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.year}</span>
            <span className="rounded-full bg-zinc-900 px-3 py-1">
              {movie.length || t('movieDetails.unknownLength')}
            </span>
            <span className="rounded-full bg-amber-400/15 px-3 py-1 font-semibold text-amber-300">
              {t('common.imdb')} {movie.rating || t('movieDetails.notAvailable')}
            </span>
            <span className="rounded-full bg-zinc-900 px-3 py-1">
              {movie.watched ? t('movieDetails.watched') : t('movieDetails.unwatched')}
            </span>
          </div>
          <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-400">
            {movie.summary || t('movieDetails.noSummary')}
          </p>
        </div>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-black">
          <div className="flex aspect-video items-center justify-center bg-zinc-950">
            <div className="max-w-md px-6 text-center">
              <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
                {t('movieDetails.player')}
              </p>
              <p className="mt-3 text-2xl font-semibold text-white">
                {movie.watched
                  ? t('movieDetails.streamReadyResume')
                  : t('movieDetails.streamReadyPrepare')}
              </p>
              <p className="mt-2 text-sm leading-6 text-zinc-500">
                {t('movieDetails.streamPlaceholder')}
              </p>
            </div>
          </div>
        </div>

        <aside className="space-y-4">
          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">{t('movieDetails.metadata')}</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="text-zinc-500">{t('movieDetails.movieId')}</dt>
                <dd className="mt-1 text-zinc-200">#{movie.id}</dd>
              </div>
              <div>
                <dt className="text-zinc-500">{t('movieDetails.imdbId')}</dt>
                <dd className="mt-1 text-zinc-200">
                  {movie.imdbId || t('movieDetails.unknown')}
                </dd>
              </div>
              <div>
                <dt className="text-zinc-500">{t('movieDetails.comments')}</dt>
                <dd className="mt-1 text-zinc-200">{movie.commentsCount}</dd>
              </div>
            </dl>
          </div>

          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">{t('movieDetails.subtitles')}</h2>
            <div className="mt-4 flex flex-wrap gap-2">
              {movie.subtitles.length === 0 ? (
                <p className="text-sm text-zinc-500">{t('movieDetails.noSubtitles')}</p>
              ) : (
                movie.subtitles.map((subtitle) => (
                  <span
                    className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300"
                    key={subtitle}
                  >
                    {subtitle}
                  </span>
                ))
              )}
            </div>
          </div>
        </aside>
      </section>

      <section className="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-5">
        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
          <div>
            <h2 className="text-2xl font-semibold text-white">{t('movieDetails.comments')}</h2>
            <p className="mt-1 text-sm text-zinc-500">
              {t('movieDetails.commentsDescription')}
            </p>
          </div>
        </div>

        {movie.watched ? (
          <form className="mt-5 space-y-3" onSubmit={handleCommentSubmit}>
            <textarea
              className="min-h-28 w-full rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-white outline-none transition placeholder:text-zinc-600 focus:border-red-400"
              maxLength={1000}
              placeholder={t('movieDetails.commentPlaceholder')}
              value={commentContent}
              onChange={(event) => setCommentContent(event.target.value)}
            />
            {commentError && (
              <p className="text-sm text-red-300" role="alert">
                {commentError}
              </p>
            )}
            <button
              className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
              type="submit"
              disabled={isPostingComment || !commentContent.trim()}
            >
              {isPostingComment
                ? t('movieDetails.publishing')
                : t('movieDetails.addComment')}
            </button>
          </form>
        ) : (
          <p className="mt-5 rounded-xl border border-dashed border-zinc-800 p-5 text-sm text-zinc-500">
            {t('movieDetails.mustWatchBeforeComment')}
          </p>
        )}

        <div className="mt-5 space-y-3">
          {comments.length === 0 ? (
            <p className="rounded-xl border border-dashed border-zinc-800 p-5 text-sm text-zinc-500">
              {t('movieDetails.noComments')}
            </p>
          ) : (
            comments.map((comment) => (
              <article className="rounded-xl border border-zinc-800 bg-zinc-950 p-4" key={comment.id}>
                <div className="flex items-center justify-between gap-3">
                  <p className="font-medium text-white">
                    {comment.author || t('movieDetails.unknownUser')}
                  </p>
                  <time className="text-xs text-zinc-500">
                    {formatCommentDate(comment.createdAt, language)}
                  </time>
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
