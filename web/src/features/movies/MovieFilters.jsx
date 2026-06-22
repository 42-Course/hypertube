import { useState } from 'react'
import { useI18n } from '../../i18n/useI18n'

const FIRST_MOVIE_YEAR = 1900
const CURRENT_YEAR = new Date().getFullYear()
const YEARS_PER_PAGE = 10
const DEFAULT_YEAR_WINDOW_START = CURRENT_YEAR - (YEARS_PER_PAGE - 1)

function getYearValue(year) {
  const value = Number(year)
  return Number.isInteger(value) ? value : null
}

function MovieFilters({ filters, onFiltersChange, sort, onSortChange }) {
  const { t } = useI18n()
  const [yearWindowStart, setYearWindowStart] = useState(DEFAULT_YEAR_WINDOW_START)
  const [isYearPickerOpen, setIsYearPickerOpen] = useState(false)
  const [draftMinYear, setDraftMinYear] = useState(filters.minYear)
  const [draftMaxYear, setDraftMaxYear] = useState(filters.maxYear)
  const selectedMinYear = getYearValue(filters.minYear)
  const selectedMaxYear = getYearValue(filters.maxYear)
  const selectedYears = [selectedMinYear, selectedMaxYear].filter(Boolean)
  const draftSelectedMinYear = getYearValue(draftMinYear)
  const draftSelectedMaxYear = getYearValue(draftMaxYear)
  const draftSelectedYears = [draftSelectedMinYear, draftSelectedMaxYear].filter(Boolean)
  const rangeStart = selectedYears.length > 0 ? Math.min(...selectedYears) : null
  const rangeEnd = selectedYears.length > 0 ? Math.max(...selectedYears) : null
  const draftRangeStart = draftSelectedYears.length > 0
    ? Math.min(...draftSelectedYears)
    : null
  const draftRangeEnd = draftSelectedYears.length > 0
    ? Math.max(...draftSelectedYears)
    : null
  const yearWindowEnd = yearWindowStart + YEARS_PER_PAGE - 1
  const visibleYears = Array.from(
    { length: YEARS_PER_PAGE },
    (_, index) => yearWindowStart + index,
  )
  const yearRangeLabel = rangeStart === null
    ? t('movies.filters.allYears')
    : rangeStart === rangeEnd
      ? String(rangeStart)
      : `${rangeStart} - ${rangeEnd}`
  const genres = [
    { label: t('movies.filters.allGenres'), value: 'all' },
    { label: t('movies.filters.genres.action'), value: 'Action' },
    { label: t('movies.filters.genres.drama'), value: 'Drama' },
    { label: t('movies.filters.genres.scienceFiction'), value: 'Science fiction' },
    { label: t('movies.filters.genres.thriller'), value: 'Thriller' },
    { label: t('movies.filters.genres.adventure'), value: 'Adventure' },
    { label: t('movies.filters.genres.animation'), value: 'Animation' },
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

  function handlePreviousYears() {
    setYearWindowStart((currentStart) =>
      Math.max(FIRST_MOVIE_YEAR, currentStart - YEARS_PER_PAGE),
    )
  }

  function handleNextYears() {
    setYearWindowStart((currentStart) =>
      Math.min(DEFAULT_YEAR_WINDOW_START, currentStart + YEARS_PER_PAGE),
    )
  }

  function handleYearClick(year) {
    if (draftRangeStart === null || (draftRangeStart !== draftRangeEnd)) {
      setDraftMinYear(String(year))
      setDraftMaxYear(String(year))
      return
    }

    setDraftMinYear(String(Math.min(draftRangeStart, year)))
    setDraftMaxYear(String(Math.max(draftRangeStart, year)))
  }

  function clearYearRange() {
    setDraftMinYear('all')
    setDraftMaxYear('all')
  }

  function openYearPicker() {
    setDraftMinYear(filters.minYear)
    setDraftMaxYear(filters.maxYear)
    setIsYearPickerOpen((isOpen) => !isOpen)
  }

  function applyYearRange() {
    onFiltersChange({ ...filters, minYear: draftMinYear, maxYear: draftMaxYear })
    setIsYearPickerOpen(false)
  }

  return (
    <div className="grid gap-3 rounded-xl border border-zinc-800 bg-zinc-900/60 p-4 md:grid-cols-4">
      <label className="block">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
          {t('movies.filters.genre')}
        </span>
        <select
          className="mt-2 h-[42px] w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 text-sm text-zinc-100 outline-none transition focus:border-red-400"
          value={filters.genre}
          onChange={(event) => updateFilter('genre', event.target.value)}
        >
          {genres.map((genre) => (
            <option key={genre.value} value={genre.value}>{genre.label}</option>
          ))}
        </select>
      </label>

      <fieldset className="relative block">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
          {t('movies.filters.year')}
        </span>
        <button
          className="mt-2 flex h-[42px] w-full items-center justify-between rounded-lg border border-zinc-800 bg-zinc-950 px-3 text-left text-sm font-normal text-zinc-100 outline-none transition hover:border-zinc-700 focus:border-red-400"
          type="button"
          onClick={openYearPicker}
        >
          <span>{yearRangeLabel}</span>
          <span className="text-zinc-500">▾</span>
        </button>

        {isYearPickerOpen && (
          <div className="absolute left-0 right-0 top-full z-30 mt-2 rounded-xl border border-zinc-800 bg-zinc-950 p-3 shadow-2xl shadow-black/40">
            <div className="mb-3 flex items-center justify-between gap-3">
              <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
                {t('movies.filters.year')}
              </span>
              <button
                className="text-xs font-medium text-zinc-500 transition hover:text-red-300"
                type="button"
                onClick={clearYearRange}
              >
                {t('movies.filters.allYears')}
              </button>
            </div>
            <div className="mb-2 flex items-center justify-between gap-2">
              <button
                aria-label={t('movies.filters.previousYears')}
                className="flex h-8 w-8 items-center justify-center rounded-lg text-zinc-400 transition hover:bg-zinc-900 hover:text-white disabled:cursor-not-allowed disabled:opacity-30"
                type="button"
                disabled={yearWindowStart <= FIRST_MOVIE_YEAR}
                onClick={handlePreviousYears}
              >
                ‹
              </button>
              <span className="text-sm font-semibold text-white">
                {yearWindowStart} - {yearWindowEnd}
              </span>
              <button
                aria-label={t('movies.filters.nextYears')}
                className="flex h-8 w-8 items-center justify-center rounded-lg text-zinc-400 transition hover:bg-zinc-900 hover:text-white disabled:cursor-not-allowed disabled:opacity-30"
                type="button"
                disabled={yearWindowStart >= DEFAULT_YEAR_WINDOW_START}
                onClick={handleNextYears}
              >
                ›
              </button>
            </div>
            <div className="grid grid-cols-2 gap-1.5">
              {visibleYears.map((year) => {
                const isRangeStart = draftRangeStart === year
                const isRangeEnd = draftRangeEnd === year
                const isInsideRange =
                  draftRangeStart !== null &&
                  draftRangeEnd !== null &&
                  year > draftRangeStart &&
                  year < draftRangeEnd
                const isSelectedEdge = isRangeStart || isRangeEnd

                return (
                  <button
                    key={year}
                    className={`rounded-lg border px-3 py-2 text-sm font-semibold transition ${
                      isSelectedEdge
                        ? 'border-red-400 bg-red-500 text-white'
                        : isInsideRange
                          ? 'border-red-500/20 bg-red-500/15 text-red-100'
                          : 'border-transparent bg-zinc-900/80 text-zinc-400 hover:border-zinc-700 hover:text-white'
                    }`}
                    type="button"
                    onClick={() => handleYearClick(year)}
                  >
                    {year}
                  </button>
                )
              })}
            </div>
            <button
              className="mt-3 w-full rounded-lg bg-red-500 px-3 py-2 text-sm font-semibold text-white transition hover:bg-red-400"
              type="button"
              onClick={applyYearRange}
            >
              {t('movies.filters.applyYears')}
            </button>
          </div>
        )}
      </fieldset>

      <label className="block">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500">
          {t('movies.filters.rating')}
        </span>
        <select
          className="mt-2 h-[42px] w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 text-sm text-zinc-100 outline-none transition focus:border-red-400"
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
          className="mt-2 h-[42px] w-full rounded-lg border border-zinc-800 bg-zinc-950 px-3 text-sm text-zinc-100 outline-none transition focus:border-red-400"
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
