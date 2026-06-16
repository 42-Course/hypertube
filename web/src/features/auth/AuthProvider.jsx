import { useCallback, useEffect, useMemo, useState } from 'react'
import { fetchCurrentUser, logout as logoutRequest } from './authApi'
import { AuthContext } from './AuthContext'
import { clearAccessToken, getAccessToken } from './authStorage'

// Single source of truth for "who is logged in". The user object always comes
// from GET /api/v1/me so it stays consistent whether the session started via
// password login or the 42 OAuth callback.
export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  // 'loading' only while we resolve an existing token; with no token we already
  // know the answer. Then it becomes 'authenticated' or 'unauthenticated'.
  // ProtectedRoute waits for this before deciding.
  const [status, setStatus] = useState(() =>
    getAccessToken() ? 'loading' : 'unauthenticated',
  )

  // Imperatively re-read the token and load the current user. Call after login
  // / the OAuth callback so the new session is reflected immediately.
  const refresh = useCallback(async () => {
    if (!getAccessToken()) {
      setUser(null)
      setStatus('unauthenticated')
      return null
    }

    try {
      const me = await fetchCurrentUser()
      setUser(me)
      setStatus('authenticated')
      return me
    } catch {
      clearAccessToken()
      setUser(null)
      setStatus('unauthenticated')
      return null
    }
  }, [])

  const signOut = useCallback(async () => {
    try {
      await logoutRequest()
    } catch {
      // Token may already be invalid offline logout is still fine.
    } finally {
      clearAccessToken()
      setUser(null)
      setStatus('unauthenticated')
    }
  }, [])

  // Resolve an existing token once on mount. setState runs only after the
  // request settles (never synchronously), so it does not cascade renders.
  useEffect(() => {
    if (!getAccessToken()) return undefined

    let active = true
    fetchCurrentUser()
      .then((me) => {
        if (!active) return
        setUser(me)
        setStatus('authenticated')
      })
      .catch(() => {
        if (!active) return
        clearAccessToken()
        setUser(null)
        setStatus('unauthenticated')
      })

    return () => {
      active = false
    }
  }, [])

  const value = useMemo(
    () => ({
      user,
      status,
      isAuthenticated: status === 'authenticated',
      refresh,
      signOut,
    }),
    [user, status, refresh, signOut],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
