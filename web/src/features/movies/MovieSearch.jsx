import { useI18n } from '../../i18n/useI18n'

function MovieSearch({
  isSearchPending = false,
  value,
  onChange,
  onSubmit,
}) {
  const { t } = useI18n()

  function handleSubmit(event) {
    event.preventDefault()
    onSubmit()
  }

  return (
    <form onSubmit={handleSubmit}>
      <label className="sr-only" htmlFor="movie-search">
        {t('movies.filters.searchLabel')}
      </label>
      <div className="relative">
        <input
          id="movie-search"
          className="min-h-12 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 pr-11 text-sm text-white outline-none transition placeholder:text-zinc-500 focus:border-red-400"
          type="search"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={t('movies.searchPlaceholder')}
        />
        {isSearchPending && (
          <span className="absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin rounded-full border-2 border-zinc-600 border-t-red-400" />
        )}
      </div>
    </form>
  )
}

export default MovieSearch
