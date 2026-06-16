import client from '../../api/client'

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

// Revoke the current access token server-side (DELETE /api/v1/session).
export async function logout() {
  await client.delete('/api/v1/session')
}

// Full-page redirect that starts the 42 (Intra) OAuth flow.
export function fortyTwoLoginUrl() {
  const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:3000'
  return `${apiUrl}/users/auth/fortytwo`
}
