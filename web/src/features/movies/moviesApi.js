import client from '../../api/client'

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
    summary: movie.summary || '',
    duration: movie.duration || null,
    subtitles: movie.subtitles || [],
    commentsCount: movie.comments_count || 0,
  }
}

function normalizeComment(comment) {
  return {
    id: comment.id,
    content: comment.content,
    createdAt: comment.created_at,
    author: comment.user?.username || null,
    authorId: comment.user?.id ?? null,
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

export async function getMovieDetails(movieId) {
  const { data } = await client.get('/api/v1/movies/' + movieId)
  return normalizeMovieDetail(data)
}

export async function getMovieComments({ movieId, page, perPage }) {
  const params = { page, per_page: perPage }
  const { data } = await client.get('/api/v1/movies/' + movieId + '/comments', { params })

  return {
    page: data.page,
    perPage: data.per_page,
    total: data.total,
    totalPages: data.total_pages,
    comments: (data.comments || []).map(normalizeComment),
  }
}

export async function createMovieComment(movieId, content) {
  const { data } = await client.post(`/api/v1/movies/${movieId}/comments`, {
    comment: { content },
  })

  return normalizeComment(data)
}
