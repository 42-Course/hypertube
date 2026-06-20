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
<<<<<<< HEAD
    author: comment.user?.username || null,
    authorId: comment.user?.id ?? null,
=======
    userId: comment.user?.id || comment.user_id,
    author: comment.user?.username,
>>>>>>> 60819ae (feat: improve frontend auth movies and public profiles)
  }
}

function buildMovieParams({ page, perPage, query, genre, year, rating, sort }) {
  const params = {
    page,
    per_page: perPage,
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

  return params
}

export async function fetchMovies({ page, perPage, query, genre, year, rating, sort }) {
  const params = buildMovieParams({ page, perPage, query, genre, year, rating, sort })
  const { data } = await client.get('/api/v1/movies', { params })
  const totalPages = data.total_pages || 1

  return {
    page: data.page || page,
    perPage: data.per_page || perPage,
    total: data.total || 0,
    totalPages,
    hasMore: (data.page || page) < totalPages,
    movies: (data.movies || []).map(normalizeMovie),
  }
}

<<<<<<< HEAD
export async function getMovieDetails(movieId) {
  const { data } = await client.get('/api/v1/movies/' + movieId)
=======
export async function searchMovies({ page, perPage, query, genre, year, rating, sort }) {
  const params = buildMovieParams({ page, perPage, query, genre, year, rating, sort })
  const { data } = await client.get('/api/v1/movies/search', { params })
  const movies = (data.movies || []).map(normalizeMovie)

  return {
    page: data.page || page,
    hasMore: movies.length > 0,
    movies,
  }
}

export async function fetchMovieDetails(movieId) {
  const { data } = await client.get(`/api/v1/movies/${movieId}`)

>>>>>>> 60819ae (feat: improve frontend auth movies and public profiles)
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

export async function updateComment(commentId, content) {
  const { data } = await client.patch(`/api/v1/comments/${commentId}`, {
    comment: { content },
  })

  return normalizeComment(data)
}

export async function deleteComment(commentId) {
  await client.delete(`/api/v1/comments/${commentId}`)
}
