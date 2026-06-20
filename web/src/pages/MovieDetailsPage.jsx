import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
<<<<<<< HEAD
import { getMovieDetails } from '../features/movies/moviesApi'
import MovieComments from '../features/movies/MovieComments'
=======
import {
  createMovieComment,
  deleteComment,
  fetchMovieComments,
  fetchMovieDetails,
  updateComment,
} from '../features/movies/moviesApi'
import { useAuth } from '../features/auth/useAuth'
>>>>>>> 60819ae (feat: improve frontend auth movies and public profiles)
import { useI18n } from '../i18n/useI18n'

function MovieDetailsPage() {
  const { movieId } = useParams()
<<<<<<< HEAD
  const { t } = useI18n()
  const [movie, setMovie] = useState(null)
  const [errorId, setErrorId] = useState(null)
=======
  const { user } = useAuth()
  const { language, t } = useI18n()
  const [movie, setMovie] = useState(null)
  const [comments, setComments] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [isPostingComment, setIsPostingComment] = useState(false)
  const [error, setError] = useState('')
  const [commentError, setCommentError] = useState('')
  const [commentContent, setCommentContent] = useState('')
  const [editingCommentId, setEditingCommentId] = useState(null)
  const [editingCommentContent, setEditingCommentContent] = useState('')
  const [pendingCommentId, setPendingCommentId] = useState(null)

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
>>>>>>> 60819ae (feat: improve frontend auth movies and public profiles)

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

<<<<<<< HEAD
  if (!isError && !isReady) {
=======
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

  function startCommentEdit(comment) {
    setCommentError('')
    setEditingCommentId(comment.id)
    setEditingCommentContent(comment.content)
  }

  function cancelCommentEdit() {
    setEditingCommentId(null)
    setEditingCommentContent('')
  }

  async function refreshComments() {
    const commentsResult = await fetchMovieComments(movie.id)

    setComments(commentsResult.comments)
    setMovie((currentMovie) => ({
      ...currentMovie,
      commentsCount: commentsResult.total,
    }))
  }

  async function handleCommentUpdate(commentId) {
    if (!editingCommentContent.trim()) {
      return
    }

    setPendingCommentId(commentId)
    setCommentError('')

    try {
      await updateComment(commentId, editingCommentContent.trim())
      await refreshComments()
      cancelCommentEdit()
    } catch {
      setCommentError(t('movieDetails.updateCommentError'))
    } finally {
      setPendingCommentId(null)
    }
  }

  async function handleCommentDelete(commentId) {
    setPendingCommentId(commentId)
    setCommentError('')

    try {
      await deleteComment(commentId)
      await refreshComments()
      if (editingCommentId === commentId) {
        cancelCommentEdit()
      }
    } catch {
      setCommentError(t('movieDetails.deleteCommentError'))
    } finally {
      setPendingCommentId(null)
    }
  }

  if (isLoading) {
>>>>>>> 60819ae (feat: improve frontend auth movies and public profiles)
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-zinc-500">
          {t('movieDetails.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">{t('common.loading')}</h1>
      </section>
    )
  }

  if (isError) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          {t('movieDetails.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          {t('movieDetails.notFound')}
        </h1>
        <Link
          className="mt-6 inline-flex rounded-lg bg-red-500 px-5 py-3 text-sm font-semibold text-white transition hover:bg-red-400"
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
            <div className="flex aspect-[2/3] items-center justify-center text-sm text-zinc-600">
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
            {movie.year ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.year}</span>
            ) : null}
            {movie.duration ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">
                {t('movieDetails.durationMinutes', { duration: movie.duration })}
              </span>
            ) : null}
            {movie.rating ? (
              <span className="rounded-full bg-amber-400/15 px-3 py-1 font-semibold text-amber-300">
                {t('common.imdb')} {movie.rating}
              </span>
            ) : null}
            <span className="rounded-full bg-zinc-900 px-3 py-1">
              {movie.watched ? t('movieDetails.watched') : t('movieDetails.unwatched')}
            </span>
          </div>
          {movie.summary ? (
            <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-400">
              {movie.summary}
            </p>
          ) : (
            <p className="mt-6 max-w-3xl text-base leading-7 text-zinc-600">
              {t('movieDetails.noSummary')}
            </p>
          )}
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
          {movie.genres.length > 0 ? (
            <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
              <h2 className="text-lg font-semibold text-white">{t('movieDetails.genres')}</h2>
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
            <h2 className="text-lg font-semibold text-white">{t('movieDetails.subtitles')}</h2>
            {movie.subtitles.length > 0 ? (
              <div className="mt-4 flex flex-wrap gap-2">
                {movie.subtitles.map((subtitle) => (
                  <span className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300" key={subtitle}>
                    {subtitle}
                  </span>
                ))}
              </div>
            ) : (
              <p className="mt-4 text-sm text-zinc-500">{t('movieDetails.noSubtitles')}</p>
            )}
          </div>
        </aside>
      </section>

<<<<<<< HEAD
      <MovieComments
        movieId={movie.id}
        initialCount={movie.commentsCount}
        watched={movie.watched}
      />
=======
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
            comments.map((comment) => {
              const commentAuthor = comment.author || t('movieDetails.unknownUser')
              const authorInitial = commentAuthor.charAt(0).toUpperCase()

              return (
                <article
                  className="rounded-xl border border-zinc-800 bg-zinc-950 p-4"
                  key={comment.id}
                >
                  <div className="flex items-center justify-between gap-3">
                    {comment.userId ? (
                      <Link
                        className="group flex items-center gap-3"
                        to={`/users/${comment.userId}`}
                      >
                        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-zinc-800 text-sm font-semibold text-zinc-200 transition group-hover:bg-red-500 group-hover:text-white">
                          {authorInitial}
                        </span>
                        <span className="font-medium text-white transition group-hover:text-red-300">
                          {commentAuthor}
                        </span>
                      </Link>
                    ) : (
                      <div className="flex items-center gap-3">
                        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-zinc-800 text-sm font-semibold text-zinc-200">
                          {authorInitial}
                        </span>
                        <p className="font-medium text-white">{commentAuthor}</p>
                      </div>
                    )}
                    <div className="flex items-center gap-3">
                      <time className="text-xs text-zinc-500">
                        {formatCommentDate(comment.createdAt, language)}
                      </time>
                      {comment.userId === user?.id && (
                        <div className="flex items-center gap-2">
                          <button
                            className="text-xs font-medium text-zinc-400 transition hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
                            type="button"
                            disabled={pendingCommentId === comment.id}
                            onClick={() => startCommentEdit(comment)}
                          >
                            {t('movieDetails.editComment')}
                          </button>
                          <button
                            className="text-xs font-medium text-red-400 transition hover:text-red-300 disabled:cursor-not-allowed disabled:opacity-50"
                            type="button"
                            disabled={pendingCommentId === comment.id}
                            onClick={() => handleCommentDelete(comment.id)}
                          >
                            {pendingCommentId === comment.id
                              ? t('movieDetails.deletingComment')
                              : t('movieDetails.deleteComment')}
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                  {editingCommentId === comment.id ? (
                    <div className="mt-3 space-y-3">
                      <textarea
                        className="min-h-24 w-full rounded-xl border border-zinc-800 bg-zinc-900 px-4 py-3 text-sm text-white outline-none transition focus:border-red-400"
                        maxLength={1000}
                        value={editingCommentContent}
                        onChange={(event) => setEditingCommentContent(event.target.value)}
                      />
                      <div className="flex flex-wrap gap-2">
                        <button
                          className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
                          type="button"
                          disabled={
                            pendingCommentId === comment.id ||
                            !editingCommentContent.trim()
                          }
                          onClick={() => handleCommentUpdate(comment.id)}
                        >
                          {pendingCommentId === comment.id
                            ? t('movieDetails.savingComment')
                            : t('movieDetails.saveComment')}
                        </button>
                        <button
                          className="rounded-lg border border-zinc-700 px-4 py-2 text-sm font-semibold text-zinc-300 transition hover:border-zinc-500 hover:text-white"
                          type="button"
                          onClick={cancelCommentEdit}
                        >
                          {t('movieDetails.cancelCommentEdit')}
                        </button>
                      </div>
                    </div>
                  ) : (
                    <p className="mt-2 text-sm leading-6 text-zinc-400">
                      {comment.content}
                    </p>
                  )}
                </article>
              )
            })
          )}
        </div>
      </section>
>>>>>>> 60819ae (feat: improve frontend auth movies and public profiles)
    </section>
  )
}

export default MovieDetailsPage
