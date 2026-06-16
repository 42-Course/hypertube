import { useI18n } from '../../i18n/useI18n'

function MovieFilters({ filters, onFiltersChange, sort, onSortChange }) {
  const { t } = useI18n()
  const genres = [
    { label: t('movies.filters.allGenres'), value: 'all' },
    { label: 'Action', value: 'Action' },
    { label: 'Drama', value: 'Drama' },
    { label: 'Science fiction', value: 'Science fiction' },
    { label: 'Thriller', value: 'Thriller' },
    { label: 'Adventure', value: 'Adventure' },
    { label: 'Animation', value: 'Animation' },
  ]
  const years = [
    { label: t('movies.filters.allYears'), value: 'all' },
    { label: '2020+', value: '2020' },
    { label: '2010-2019', value: '2010' },
    { label: t('movies.filters.before2010'), value: 'before-2010' },
  ]
  const ratings = [
    { label: t('movies.filters.allRatings'), value: 'all' },
    { label: '8+', value: '8' },
    { label: '7+', value: '7' },
    { label: '6+', value: '6' },
  ]
  const sortOptions = [
    { label: t('movies.sort.popularity'), value: 'popularity' },
    { label: t('movies.sort.title'), value: 'title' },
    { label: t('movies.sort.rating'), value: 'rating' },
    { label: t('movies.sort.year'), value: 'year' },
  ]

  function updateFilter(name, value) {
    onFiltersChange({ ...filters, [name]: value })
  }

  return (
    <div className="grid gap-3 rounded-xl border border-zinc-800 bg-zinc-900/60 p-4 md:grid-cols-4">
      <label className="block">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
          {t('movies.filters.genre')}
        </span>
        <select
          className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2.5 text-sm text-zinc-100 outline-none transition focus:border-red-400"
          value={filters.genre}
          onChange={(event) => updateFilter('genre', event.target.value)}
        >
          {genres.map((genre) => (
            <option key={genre.value} value={genre.value}>{genre.label}</option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
          {t('movies.filters.year')}
        </span>
        <select
          className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2.5 text-sm text-zinc-100 outline-none transition focus:border-red-400"
          value={filters.year}
          onChange={(event) => updateFilter('year', event.target.value)}
        >
          {years.map((year) => (
            <option key={year.value} value={year.value}>{year.label}</option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
          {t('movies.filters.rating')}
        </span>
        <select
          className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2.5 text-sm text-zinc-100 outline-none transition focus:border-red-400"
          value={filters.rating}
          onChange={(event) => updateFilter('rating', event.target.value)}
        >
          {ratings.map((rating) => (
            <option key={rating.value} value={rating.value}>{rating.label}</option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
          {t('movies.sort.label')}
        </span>
        <select
          className="mt-2 w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-2.5 text-sm text-zinc-100 outline-none transition focus:border-red-400"
          value={sort}
          onChange={(event) => onSortChange(event.target.value)}
        >
          {sortOptions.map((option) => (
            <option key={option.value} value={option.value}>{option.label}</option>
          ))}
        </select>
      </label>
    </div>
  )
}

export default MovieFilters
