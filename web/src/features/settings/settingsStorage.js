// Persisted client-side preferences (localStorage). These are per-browser and
// do not require a round-trip to the API.

export const MOVIE_SOURCES = {
  local: 'local',
  online: 'online',
}

const MOVIE_SOURCE_STORAGE_KEY = 'hypertube.movieSource'
const DEFAULT_MOVIE_SOURCE = MOVIE_SOURCES.local

function isValidMovieSource(value) {
  return value === MOVIE_SOURCES.local || value === MOVIE_SOURCES.online
}

// Read the preferred movie search source ('local' = server catalog,
// 'online' = external providers). Falls back to the default when unset or
// when storage is unavailable (e.g. private mode).
export function getMovieSource() {
  try {
    const stored = window.localStorage.getItem(MOVIE_SOURCE_STORAGE_KEY)
    return isValidMovieSource(stored) ? stored : DEFAULT_MOVIE_SOURCE
  } catch {
    return DEFAULT_MOVIE_SOURCE
  }
}

// Persist the preferred movie search source. Returns the value that ended up
// being stored (the default when the input is invalid).
export function saveMovieSource(value) {
  const nextValue = isValidMovieSource(value) ? value : DEFAULT_MOVIE_SOURCE

  try {
    window.localStorage.setItem(MOVIE_SOURCE_STORAGE_KEY, nextValue)
  } catch {
    // Ignore storage failures: the preference simply won't persist.
  }

  return nextValue
}
