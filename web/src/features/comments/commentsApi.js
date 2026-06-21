import client from '../../api/client'

function normalizeComment(comment) {
  return {
    id: comment.id,
    content: comment.content,
    createdAt: comment.created_at,
    author: comment.user?.username || null,
    authorId: comment.user?.id ?? null,
  }
}

export async function fetchLatestComments({ page = 1, perPage = 20 } = {}) {
  const { data } = await client.get('/api/v1/comments', {
    params: { page, per_page: perPage },
  })

  return {
    page: data.page || page,
    perPage: data.per_page || perPage,
    total: data.total || 0,
    totalPages: data.total_pages || 1,
    comments: (data.comments || []).map(normalizeComment),
  }
}
