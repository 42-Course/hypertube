import { useEffect, useMemo, useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { fetchLatestComments } from '../features/comments/commentsApi'
import { useI18n } from '../i18n/useI18n'

const COMMENTS_PER_PAGE = 20

function formatCommentDate(date, language) {
  if (!date) return ''

  return new Intl.DateTimeFormat(language === 'fr' ? 'fr-FR' : 'en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(date))
}

function ActivityPage() {
  const { language, t } = useI18n()
  const location = useLocation()
  const [comments, setComments] = useState([])
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const [status, setStatus] = useState('loading')
  const [error, setError] = useState('')

  const hasMore = page < totalPages
  const isLoadingMore = status === 'loading-more'
  const skeletonCount = status === 'loading' ? 6 : 3

  const formattedComments = useMemo(
    () =>
      comments.map((comment) => ({
        ...comment,
        formattedDate: formatCommentDate(comment.createdAt, language),
      })),
    [comments, language],
  )

  useEffect(() => {
    let active = true

    async function loadComments() {
      setStatus('loading')
      setError('')

      try {
        const data = await fetchLatestComments({ page: 1, perPage: COMMENTS_PER_PAGE })

        if (!active) return
        setComments(data.comments)
        setPage(data.page)
        setTotalPages(data.totalPages)
        setStatus('ready')
      } catch {
        if (!active) return
        setError(t('activity.loadError'))
        setStatus('error')
      }
    }

    loadComments()

    return () => {
      active = false
    }
  }, [t])

  async function handleLoadMore() {
    if (!hasMore || isLoadingMore) return

    setStatus('loading-more')
    setError('')

    try {
      const nextPage = page + 1
      const data = await fetchLatestComments({
        page: nextPage,
        perPage: COMMENTS_PER_PAGE,
      })

      setComments((currentComments) => [...currentComments, ...data.comments])
      setPage(data.page)
      setTotalPages(data.totalPages)
      setStatus('ready')
    } catch {
      setError(t('activity.loadMoreError'))
      setStatus('ready')
    }
  }

  return (
    <section className="py-10">
      <div className="mb-8">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          {t('activity.label')}
        </p>
        <h1 className="mt-3 text-4xl font-semibold tracking-tight text-white">
          {t('activity.title')}
        </h1>
      </div>

      {status === 'loading' && (
        <div className="space-y-4">
          {Array.from({ length: skeletonCount }).map((_, index) => (
            <article
              className="rounded-3xl border border-zinc-800 bg-zinc-900/60 p-5"
              key={index}
            >
              <div className="flex items-start gap-4">
                <div className="h-12 w-12 animate-pulse rounded-full bg-zinc-800" />
                <div className="flex-1">
                  <div className="h-4 w-40 animate-pulse rounded bg-zinc-800" />
                  <div className="mt-4 h-4 w-full animate-pulse rounded bg-zinc-800/80" />
                  <div className="mt-2 h-4 w-2/3 animate-pulse rounded bg-zinc-800/80" />
                </div>
              </div>
            </article>
          ))}
        </div>
      )}

      {status === 'error' && (
        <div className="rounded-3xl border border-red-500/30 bg-red-500/10 p-6 text-sm text-red-100">
          {error}
        </div>
      )}

      {status !== 'loading' && status !== 'error' && comments.length === 0 && (
        <div className="rounded-3xl border border-zinc-800 bg-zinc-900/60 p-8 text-center">
          <h2 className="text-xl font-semibold text-white">{t('activity.emptyTitle')}</h2>
          <p className="mt-2 text-sm text-zinc-400">{t('activity.emptyDescription')}</p>
        </div>
      )}

      {status !== 'loading' && status !== 'error' && comments.length > 0 && (
        <div className="space-y-4">
          {formattedComments.map((comment) => (
            <article
              className="rounded-3xl border border-zinc-800 bg-zinc-900/60 p-5"
              key={comment.id}
            >
              <div className="flex items-start gap-4">
                <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-red-500/80 to-zinc-800 text-base font-semibold text-white">
                  {comment.author?.charAt(0).toUpperCase() || '?'}
                </div>

                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
                    {comment.authorId ? (
                      <Link
                        className="font-semibold text-white transition hover:text-red-300"
                        state={{
                          from: `${location.pathname}${location.search}`,
                          backLabel: t('publicProfile.backToActivity'),
                        }}
                        to={`/users/${comment.authorId}`}
                      >
                        {comment.author || t('activity.unknownUser')}
                      </Link>
                    ) : (
                      <span className="font-semibold text-white">
                        {comment.author || t('activity.unknownUser')}
                      </span>
                    )}
                    <span className="text-zinc-600">•</span>
                    <time className="text-zinc-500" dateTime={comment.createdAt}>
                      {comment.formattedDate}
                    </time>
                  </div>

                  <p className="mt-3 whitespace-pre-line text-sm leading-6 text-zinc-300">
                    {comment.content}
                  </p>
                </div>
              </div>
            </article>
          ))}

          {isLoadingMore && (
            <div className="space-y-4">
              {Array.from({ length: skeletonCount }).map((_, index) => (
                <article
                  className="rounded-3xl border border-zinc-800 bg-zinc-900/60 p-5"
                  key={index}
                >
                  <div className="h-4 w-1/3 animate-pulse rounded bg-zinc-800" />
                  <div className="mt-4 h-4 w-full animate-pulse rounded bg-zinc-800/80" />
                </article>
              ))}
            </div>
          )}

          {error && (
            <p className="rounded-2xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-100">
              {error}
            </p>
          )}

          {hasMore && (
            <button
              className="w-full rounded-2xl border border-zinc-700 px-5 py-3 text-sm font-semibold text-zinc-100 transition hover:border-red-400 hover:text-white disabled:cursor-not-allowed disabled:opacity-60"
              type="button"
              disabled={isLoadingMore}
              onClick={handleLoadMore}
            >
              {isLoadingMore ? t('activity.loadingMore') : t('activity.loadMore')}
            </button>
          )}
        </div>
      )}
    </section>
  )
}

export default ActivityPage
