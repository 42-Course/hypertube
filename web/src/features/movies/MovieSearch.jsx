import { useI18n } from '../../i18n/useI18n'

function MovieSearch({ value, onChange }) {
  const { t } = useI18n()

  return (
    <form className="flex flex-col gap-3 sm:flex-row" onSubmit={(event) => event.preventDefault()}>
      <label className="sr-only" htmlFor="movie-search">
        Rechercher une video
      </label>
      <input
        id="movie-search"
        className="min-h-12 flex-1 rounded-lg border border-zinc-800 bg-zinc-900 px-4 text-sm text-white outline-none transition placeholder:text-zinc-500 focus:border-red-400"
        type="search"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={t('movies.searchPlaceholder')}
      />
      <button
        className="min-h-12 rounded-lg bg-red-500 px-6 text-sm font-semibold text-white transition hover:bg-red-400"
        type="submit"
      >
        {t('movies.searchButton')}
      </button>
    </form>
  )
}

export default MovieSearch
