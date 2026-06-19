import client from '../../api/client'

function normalizeMovie(movie) {
  return {
    id: movie.id,
    imdbId: movie.imdb_id,
    title: movie.title,
    year: movie.year,
    rating: Number(movie.rating) || 0,
    coverUrl: movie.cover_url,
    genre: movie.genres?.[0] || 'Unknown',
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