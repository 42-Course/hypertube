import { useI18n } from '../../i18n/useI18n'

function MovieSearch({ isDisabled = false, isSearching, value, onChange, onSubmit }) {
  const { t } = useI18n()

  function handleSubmit(event) {
    event.preventDefault()
    onSubmit()
  }

  return (
    <form className="flex flex-col gap-3 sm:flex-row" onSubmit={handleSubmit}>
      <label className="sr-only" htmlFor="movie-search">
        {t('movies.filters.searchLabel')}
      </label>
      <div className="relative flex-1">
        <input
          id="movie-search"
          className="min-h-12 w-full rounded-lg border border-zinc-800 bg-zinc-900 px-4 pr-11 text-sm text-white outline-none transition placeholder:text-zinc-500 focus:border-red-400"
          type="search"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          placeholder={t('movies.searchPlaceholder')}
        />
        {isSearching && (
          <span className="absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin rounded-full border-2 border-zinc-600 border-t-red-400" />
        )}
      </div>
      <button
        className="inline-flex min-h-12 items-center justify-center gap-2 rounded-lg bg-red-500 px-6 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-70"
        type="submit"
        disabled={isDisabled}
      >
        {isSearching && (
          <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" />
        )}
        {isSearching ? t('movies.searchingButton') : t('movies.searchButton')}
      </button>
    </form>
  )
}

export default MovieSearch
