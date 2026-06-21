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

function normalizeUser(user) {
  if (!user) return null
  return {
    id: user.id,
    username: user.username,
    email: user.email,
    firstName: user.first_name,
    lastName: user.last_name,
    profilePictureUrl: user.profile_picture_url,
    preferredLanguage: user.preferred_language,
  }
}

// The authenticated user's own profile (GET /api/v1/me)
export async function fetchCurrentUser() {
  const { data } = await client.get('/api/v1/me')
  return normalizeUser(data)
}

export async function fetchPublicUser(userId) {
  const { data } = await client.get(`/api/v1/users/${userId}`)
  return normalizeUser(data)
}

export async function fetchUsers() {
  const { data } = await client.get('/api/v1/users')
  return data.map(normalizeUser)
}

// Email/username + password login. No OAuth client_id/client_secret needed:
// the backend mints a first-party token server-side (POST /api/v1/session).
export async function login({ login, password }) {
  const { data } = await client.post('/api/v1/session', { login, password })
  return {
    accessToken: data.access_token,
    tokenType: data.token_type,
    expiresIn: data.expires_in,
    user: normalizeUser(data.user),
  }
}

export async function register({ email, username, firstName, lastName, password }) {
  const { data } = await client.post('/api/v1/users', {
    user: {
      email,
      username,
      first_name: firstName,
      last_name: lastName,
      password,
      preferred_language: 'en',
    },
  })

  return normalizeUser(data)
}

export async function fetchUserMovies(userId, { page = 1, perPage = 20 } = {}) {
  const { data } = await client.get(`/api/v1/users/${userId}/movies`, {
    params: { page, per_page: perPage },
  })

  return {
    page: data.page || page,
    perPage: data.per_page || perPage,
    total: data.total || 0,
    totalPages: data.total_pages || 1,
    movies: (data.movies || []).map(normalizeMovie),
  }
}

export async function updateProfile(
  userId,
  {
    username,
    email,
    firstName,
    lastName,
    password,
    preferredLanguage,
    profilePictureUrl,
    avatarFile,
  },
) {
  if (avatarFile) {
    const formData = new FormData()
    formData.append('username', username)
    formData.append('email', email)
    formData.append('first_name', firstName)
    formData.append('last_name', lastName)
    formData.append('preferred_language', preferredLanguage)
    formData.append('profile_picture_url', profilePictureUrl || '')
    formData.append('avatar', avatarFile)

    if (password) {
      formData.append('password', password)
    }

    const { data } = await client.patch(`/api/v1/users/${userId}`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    })

    return normalizeUser(data)
  }

  const userPayload = {
    username,
    email,
    first_name: firstName,
    last_name: lastName,
    preferred_language: preferredLanguage,
    profile_picture_url: profilePictureUrl,
  }

  if (password) {
    userPayload.password = password
  }

  const { data } = await client.patch(`/api/v1/users/${userId}`, {
    user: userPayload,
  })

  return normalizeUser(data)
}

export async function requestPasswordReset(email) {
  const { data } = await client.post('/api/v1/password', {
    user: { email },
  })

  return data
}

export async function resetPassword({ token, password, passwordConfirmation }) {
  const { data } = await client.patch('/api/v1/password', {
    user: {
      reset_password_token: token,
      password,
      password_confirmation: passwordConfirmation,
    },
  })

  return data
}

// Revoke the current access token server-side (DELETE /api/v1/session).
export async function logout() {
  await client.delete('/api/v1/session')
}

function providerLoginUrl(provider) {
  const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:3000'
  return `${apiUrl}/users/auth/${provider}`
}

// Full-page redirect that starts the 42 (Intra) OAuth flow.
export function fortyTwoLoginUrl() {
  return providerLoginUrl('fortytwo')
}

// Full-page redirect that starts the Google OAuth flow.
export function googleLoginUrl() {
  return providerLoginUrl('google_oauth2')
}
