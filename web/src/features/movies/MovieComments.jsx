import { useEffect, useState } from 'react'
import { createMovieComment, getMovieComments } from './moviesApi'
import { useI18n } from '../../i18n/useI18n'

const PER_PAGE_OPTIONS = [5, 10, 20, 50]
const DEFAULT_PER_PAGE = 10

function formatDate(value, language) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return new Intl.DateTimeFormat(language === 'fr' ? 'fr-FR' : 'en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date)
}

function MovieComments({ movieId, initialCount = 0, watched = false }) {
  const { language, t } = useI18n()
  const [page, setPage] = useState(1)
  const [perPage, setPerPage] = useState(DEFAULT_PER_PAGE)
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('loading')
  const [refreshKey, setRefreshKey] = useState(0)
  const [commentContent, setCommentContent] = useState('')
  const [isPosting, setIsPosting] = useState(false)
  const [postError, setPostError] = useState('')

  // Refetch whenever the movie, page, page size, or refresh trigger changes. The
  // carousel only ever holds one page worth of comments, so each change is a
  // fresh request.
  useEffect(() => {
    if (!movieId) return undefined
    let active = true
    setStatus('loading')

    getMovieComments({ movieId, page, perPage })
      .then((result) => {
        if (!active) return
        setData(result)
        setStatus('ready')
      })
      .catch(() => {
        if (!active) return
        setStatus('error')
      })

    return () => {
      active = false
    }
  }, [movieId, page, perPage, refreshKey])

  // Reset to the first page when the page size changes so we never land on a
  // page index that no longer exists with the new per_page value.
  function changePerPage(nextPerPage) {
    setPerPage(nextPerPage)
    setPage(1)
  }

  async function handleSubmit(event) {
    event.preventDefault()

    if (!commentContent.trim() || !watched) {
      return
    }

    setIsPosting(true)
    setPostError('')

    try {
      await createMovieComment(movieId, commentContent.trim())
      setCommentContent('')
      // Jump back to the first page and refetch so the new comment is visible.
      setPage(1)
      setRefreshKey((current) => current + 1)
    } catch {
      setPostError(t('movieDetails.publishError'))
    } finally {
      setIsPosting(false)
    }
  }

  const totalPages = data?.totalPages ?? 0
  const total = data?.total ?? initialCount
  const comments = data?.comments ?? []
  const canPrev = page > 1
  const canNext = totalPages > 0 && page < totalPages

  return (
    <section className="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-5">
      <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
        <div>
          <h2 className="text-2xl font-semibold text-white">
            {t('movieDetails.comments')}
            <span className="ml-2 text-base font-normal text-zinc-500">({total})</span>
          </h2>
          <p className="mt-1 text-sm text-zinc-500">{t('movieDetails.commentsDescription')}</p>
        </div>

        <label className="flex items-center gap-2 text-sm text-zinc-400">
          <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
            {t('movieDetails.perPage')}
          </span>
          <select
            className="rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none transition focus:border-red-400"
            value={perPage}
            onChange={(event) => changePerPage(Number(event.target.value))}
          >
            {PER_PAGE_OPTIONS.map((option) => (
              <option key={option} value={option}>{option}</option>
            ))}
          </select>
        </label>
      </div>

      {watched ? (
        <form className="mt-5 space-y-3" onSubmit={handleSubmit}>
          <textarea
            className="min-h-28 w-full rounded-xl border border-zinc-800 bg-zinc-950 px-4 py-3 text-sm text-white outline-none transition placeholder:text-zinc-600 focus:border-red-400"
            maxLength={1000}
            placeholder={t('movieDetails.commentPlaceholder')}
            value={commentContent}
            onChange={(event) => setCommentContent(event.target.value)}
          />
          {postError && (
            <p className="text-sm text-red-300" role="alert">
              {postError}
            </p>
          )}
          <button
            className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-60"
            type="submit"
            disabled={isPosting || !commentContent.trim()}
          >
            {isPosting ? t('movieDetails.publishing') : t('movieDetails.addComment')}
          </button>
        </form>
      ) : (
        <p className="mt-5 rounded-xl border border-dashed border-zinc-800 p-5 text-sm text-zinc-500">
          {t('movieDetails.mustWatchBeforeComment')}
        </p>
      )}

      <div className="mt-5 space-y-3">
        {status === 'loading' ? (
          <p className="rounded-xl border border-dashed border-zinc-800 p-5 text-sm text-zinc-500">
            {t('movieDetails.loadingComments')}
          </p>
        ) : null}

        {status === 'error' ? (
          <p className="rounded-xl border border-dashed border-red-500/40 p-5 text-sm text-red-400">
            {t('movieDetails.commentsLoadError')}
          </p>
        ) : null}

        {status === 'ready' && comments.length === 0 ? (
          <p className="rounded-xl border border-dashed border-zinc-800 p-5 text-sm text-zinc-500">
            {t('movieDetails.noComments')}
          </p>
        ) : null}

        {status === 'ready'
          ? comments.map((comment) => (
              <article
                className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-4"
                key={comment.id}
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="text-sm font-semibold text-white">
                    {comment.author || t('movieDetails.unknownUser')}
                  </span>
                  <span className="text-xs text-zinc-500">
                    {formatDate(comment.createdAt, language)}
                  </span>
                </div>
                <p className="mt-2 text-sm leading-6 text-zinc-300">{comment.content}</p>
              </article>
            ))
          : null}
      </div>

      {totalPages > 1 ? (
        <div className="mt-5 flex flex-wrap items-center justify-between gap-3">
          <button
            className="rounded-lg border border-zinc-800 px-3 py-2 text-sm font-medium text-zinc-300 transition enabled:hover:border-red-400 enabled:hover:text-white disabled:opacity-40"
            type="button"
            onClick={() => setPage((current) => Math.max(1, current - 1))}
            disabled={!canPrev}
          >
            {t('movieDetails.previous')}
          </button>

          <div className="flex flex-wrap items-center gap-1.5">
            {Array.from({ length: totalPages }, (_, index) => index + 1).map((pageNumber) => (
              <button
                className={`min-w-9 rounded-lg px-3 py-2 text-sm font-medium transition ${
                  pageNumber === page
                    ? 'bg-red-500 text-white'
                    : 'border border-zinc-800 text-zinc-300 hover:border-red-400 hover:text-white'
                }`}
                key={pageNumber}
                type="button"
                onClick={() => setPage(pageNumber)}
                aria-current={pageNumber === page ? 'page' : undefined}
              >
                {pageNumber}
              </button>
            ))}
          </div>

          <button
            className="rounded-lg border border-zinc-800 px-3 py-2 text-sm font-medium text-zinc-300 transition enabled:hover:border-red-400 enabled:hover:text-white disabled:opacity-40"
            type="button"
            onClick={() => setPage((current) => current + 1)}
            disabled={!canNext}
          >
            {t('movieDetails.next')}
          </button>
        </div>
      ) : null}
    </section>
  )
}

export default MovieComments
