const SETTINGS_KEY = 'hypertube_settings'
const DEFAULT_MOVIES_PER_PAGE = 20
export const MOVIES_PER_PAGE_OPTIONS = [10, 20, 40]

function readSettings() {
  try {
    return JSON.parse(localStorage.getItem(SETTINGS_KEY)) || {}
  } catch {
    return {}
  }
}

function saveSettings(settings) {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings))
}

function normalizeMoviesPerPage(value) {
  const numericValue = Number(value)

  return MOVIES_PER_PAGE_OPTIONS.includes(numericValue)
    ? numericValue
    : DEFAULT_MOVIES_PER_PAGE
}

export function getMoviesPerPage() {
  return normalizeMoviesPerPage(readSettings().moviesPerPage)
}

export function saveMoviesPerPage(value) {
  const settings = readSettings()
  const moviesPerPage = normalizeMoviesPerPage(value)

  saveSettings({ ...settings, moviesPerPage })
  return moviesPerPage
}
