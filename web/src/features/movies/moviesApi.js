import client from '../../api/client'

function formatDuration(duration) {
  if (!duration) return null
  if (typeof duration === 'string') return duration

  const hours = Math.floor(duration / 60)
  const minutes = duration % 60

  if (hours === 0) return `${minutes}m`
  if (minutes === 0) return `${hours}h`

  return `${hours}h ${minutes}m`
}

function normalizeMovie(movie) {
  return {
    id: movie.id,
    imdbId: movie.imdb_id,
    title: movie.title,
    year: movie.year,
    rating: Number(movie.rating) || 0,
    coverUrl: movie.cover_url,
    genre: movie.genres?.[0] || null,
    genres: movie.genres || [],
    watched: Boolean(movie.watched),
  }
}

function normalizeMovieDetail(movie) {
  return {
    ...normalizeMovie(movie),
    summary: movie.summary,
    length: formatDuration(movie.duration),
    subtitles: movie.subtitles || [],
    commentsCount: movie.comments_count || 0,
  }
}

function normalizeComment(comment) {
  return {
    id: comment.id,
    content: comment.content,
    createdAt: comment.created_at,
    author: comment.user?.username,
  }
}

export async function searchMovies({ page, query, genre, year, rating, sort }) {
  const params = {
    page,
    query: query || undefined,
    sort: sort === 'title' ? 'name' : sort,
    order: sort === 'title' ? 'asc' : 'desc',
    genre: genre === 'all' ? undefined : genre,
    min_rating: rating === 'all' ? undefined : rating,
  }

  if (year === '2020') {
    params.min_year = 2020
  }

  if (year === '2010') {
    params.min_year = 2010
    params.max_year = 2019
  }

  if (year === 'before-2010') {
    params.max_year = 2009
  }

  const { data } = await client.get('/api/v1/movies/search', { params })

  return {
    page: data.page || page,
    movies: (data.movies || []).map(normalizeMovie),
  }
}

export async function fetchMovieDetails(movieId) {
  const { data } = await client.get(`/api/v1/movies/${movieId}`)

  return normalizeMovieDetail(data)
}

export async function fetchMovieComments(movieId, page = 1) {
  const { data } = await client.get(`/api/v1/movies/${movieId}/comments`, {
    params: { page },
  })

  return {
    page: data.page || page,
    total: data.total || 0,
    totalPages: data.total_pages || 1,
    comments: (data.comments || []).map(normalizeComment),
  }
}

export async function createMovieComment(movieId, content) {
  const { data } = await client.post(`/api/v1/movies/${movieId}/comments`, {
    comment: { content },
  })

  return normalizeComment(data)
}
