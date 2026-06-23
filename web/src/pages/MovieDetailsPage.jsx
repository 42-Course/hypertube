import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import HlsPlayer from '../features/movies/HlsPlayer'
import MovieComments from '../features/movies/MovieComments'
import MoviePosterFallback from '../features/movies/MoviePosterFallback'
import {
  fetchSubtitleVttUrl,
  getMovieDetails,
  markMovieUnwatched,
  markMovieWatched,
  updateMovieDuration,
} from '../features/movies/moviesApi'
import { useMoviePlayback } from '../features/movies/useMoviePlayback'
import { useI18n } from '../i18n/useI18n'

function formatBytes(bytes) {
  if (!bytes || bytes <= 0) {
    return '0 MB'
  }
  const mb = bytes / (1024 * 1024)
  if (mb >= 1024) {
    return `${(mb / 1024).toFixed(2)} GB`
  }
  return `${mb.toFixed(0)} MB`
}

function formatClock(totalSeconds) {
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) {
    return '0:00'
  }
  const seconds = Math.floor(totalSeconds)
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const remainder = seconds % 60
  const mm = hours > 0 ? String(minutes).padStart(2, '0') : String(minutes)
  return `${hours > 0 ? `${hours}:` : ''}${mm}:${String(remainder).padStart(2, '0')}`
}

function MovieDetailsPage() {
  const { movieId } = useParams()
  const { t } = useI18n()
  const [movie, setMovie] = useState(null)
  const [errorId, setErrorId] = useState(null)
  const [watchStatusError, setWatchStatusError] = useState('')
  const [isUpdatingWatchStatus, setIsUpdatingWatchStatus] = useState(false)

  // hls.js native renditions (used on the VOD master playlist path).
  const [nativeTracks, setNativeTracks] = useState({ audio: [], subtitle: [] })
  const [nativeAudioIndex, setNativeAudioIndex] = useState(0)
  const [nativeSubtitleIndex, setNativeSubtitleIndex] = useState(-1)

  // OpenSubtitles overlay (fetched from the API, rendered as a <track>).
  const [osLanguage, setOsLanguage] = useState('')
  const [osSubtitle, setOsSubtitle] = useState(null)

  // Global seek bar: null unless the user is actively scrubbing the timeline.
  const [scrubSeconds, setScrubSeconds] = useState(null)

  const movieRef = useRef(null)
  useEffect(() => {
    movieRef.current = movie
  }, [movie])

  // Mark the movie watched the instant playback starts (not after HLS is ready).
  const handlePlaybackStarted = useCallback(async () => {
    const current = movieRef.current
    if (!current || current.watched) {
      return
    }
    try {
      const updated = await markMovieWatched(current.id)
      setMovie(updated)
    } catch {
      // Watched tracking is best-effort; never interrupt playback.
    }
  }, [])

  const playback = useMoviePlayback(movieId, { onPlaybackStarted: handlePlaybackStarted })

  useEffect(() => {
    let active = true

    getMovieDetails(movieId)
      .then((data) => {
        if (!active) {
          return
        }
        setMovie(data)
        setErrorId(null)
      })
      .catch(() => {
        if (!active) {
          return
        }
        setErrorId(movieId)
      })

    return () => {
      active = false
    }
  }, [movieId])

  // Load (and revoke) the OpenSubtitles VTT object URL when the language changes.
  // Stored together with its language so an empty selection simply yields no
  // matching track (avoids a synchronous state reset inside the effect body).
  const movieIdValue = movie?.id
  useEffect(() => {
    if (!osLanguage || !movieIdValue) {
      return undefined
    }
    let active = true
    let createdUrl = null
    fetchSubtitleVttUrl(movieIdValue, osLanguage)
      .then((url) => {
        if (!active) {
          URL.revokeObjectURL(url)
          return
        }
        createdUrl = url
        setOsSubtitle({ language: osLanguage, url })
      })
      .catch(() => {})
    return () => {
      active = false
      if (createdUrl) {
        URL.revokeObjectURL(createdUrl)
      }
    }
  }, [osLanguage, movieIdValue])

  // Persist the runtime to the API once the torrent/transcoder reveals it (the
  // metadata sources almost always leave duration empty). Runs once: the guard
  // stops firing as soon as the movie reports a duration.
  const playbackDurationSeconds = playback.durationSeconds
  const movieDuration = movie?.duration
  useEffect(() => {
    if (!movieIdValue || !playbackDurationSeconds || playbackDurationSeconds <= 0 || movieDuration) {
      return undefined
    }
    let active = true
    updateMovieDuration(movieIdValue, playbackDurationSeconds)
      .then((updated) => {
        if (active) {
          setMovie(updated)
        }
      })
      .catch(() => {})
    return () => {
      active = false
    }
  }, [playbackDurationSeconds, movieIdValue, movieDuration])

  const isError = errorId === movieId
  const isReady = movie != null && String(movie.id) === movieId

  if (!isError && !isReady) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-zinc-500">
          {t('movieDetails.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">{t('common.loading')}</h1>
      </section>
    )
  }

  if (isError) {
    return (
      <section className="py-20 text-center">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
          {t('movieDetails.label')}
        </p>
        <h1 className="mt-4 text-3xl font-semibold text-white">
          {t('movieDetails.notFound')}
        </h1>
        <Link
          className="mt-6 inline-flex rounded-lg bg-red-500 px-5 py-3 text-sm font-semibold text-white transition hover:bg-red-400"
          to="/movies"
        >
          {t('movieDetails.backToCatalog')}
        </Link>
      </section>
    )
  }

  const genres = movie.genres?.length
    ? movie.genres.join(' / ')
    : movie.genre || t('movieDetails.unknownGenre')
  const hasCredits =
    Boolean(movie.director) || movie.producers.length > 0 || movie.cast.length > 0

  const isPreparing = playback.status === 'preparing' || playback.status === 'buffering'
  const isVod = playback.mode === 'vod'

  // Audio options: hls.js native renditions for VOD, else the interactive
  // session's audio_tracks (a server re-seek switches the rendition).
  const audioOptions = isVod
    ? nativeTracks.audio
    : playback.audioTracks.filter((track) => track.supported !== false)
  const selectedAudioValue = isVod ? nativeAudioIndex : playback.selectedAudio

  const handleAudioChange = (event) => {
    const value = Number(event.target.value)
    if (isVod) {
      setNativeAudioIndex(value)
    } else {
      playback.selectAudio(value)
    }
  }

  // Embedded / in-torrent subtitle options from the stream.
  const streamSubtitleOptions = isVod
    ? nativeTracks.subtitle
    : playback.streamSubtitles.filter((track) => track.supported !== false)
  const selectedStreamSubtitleValue = isVod
    ? nativeSubtitleIndex
    : playback.selectedStreamSubtitle

  const handleStreamSubtitleChange = (event) => {
    const raw = event.target.value
    if (isVod) {
      setNativeSubtitleIndex(raw === '' ? -1 : Number(raw))
    } else {
      playback.selectStreamSubtitle(raw === '' ? null : Number(raw))
    }
  }

  // Global timeline: lets the viewer jump anywhere in the movie (the streaming
  // service starts a new transcode there and prioritizes those pieces), even
  // before the whole torrent has downloaded. Interactive sessions only — VOD
  // uses the player's own native scrubber.
  const canSeekTimeline =
    playback.mode === 'interactive' && Number(playback.durationSeconds) > 0 && Boolean(playback.playlistUrl)
  const timelineMax = Math.floor(Number(playback.durationSeconds) || 0)
  const timelineValue =
    scrubSeconds != null ? scrubSeconds : Math.min(Math.floor(playback.globalTime || 0), timelineMax)

  const commitSeek = () => {
    if (scrubSeconds != null) {
      playback.seekTo(scrubSeconds)
      setScrubSeconds(null)
    }
  }

  const osLanguages = movie.subtitles || []
  const extraTracks =
    osLanguage && osSubtitle?.language === osLanguage
      ? [{ src: osSubtitle.url, srcLang: osLanguage, label: osLanguage, default: true }]
      : []

  const mediaStateLabel = playback.mediaState
    ? t(`movieDetails.mediaState.${playback.mediaState}`)
    : t(`movieDetails.streamStatus.${playback.status}`)
  const isDownloading = playback.progress.bytesTotal > 0 && !playback.progress.complete
  const showProgress = isDownloading && !isVod

  async function handlePreparePlayback() {
    await playback.start()
  }

  async function handleMarkUnwatched() {
    setIsUpdatingWatchStatus(true)
    setWatchStatusError('')

    try {
      const updatedMovie = await markMovieUnwatched(movie.id)
      setMovie(updatedMovie)
    } catch {
      setWatchStatusError(t('movieDetails.watchStatusError'))
    } finally {
      setIsUpdatingWatchStatus(false)
    }
  }

  return (
    <section className="space-y-7 sm:space-y-10">
      <Link
        className="inline-flex text-sm font-medium text-zinc-400 transition hover:text-white"
        to="/movies"
      >
        {t('movieDetails.backToCatalog')}
      </Link>

      <section className="grid gap-6 lg:grid-cols-[300px_1fr] xl:grid-cols-[340px_1fr]">
        <div className="mx-auto w-full max-w-[220px] overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-900 sm:max-w-[280px] lg:max-w-none">
          {movie.coverUrl ? (
            <img
              className="h-full w-full object-cover"
              src={movie.coverUrl}
              alt={t('movieDetails.posterAlt', { title: movie.title })}
            />
          ) : (
            <MoviePosterFallback className="aspect-[2/3]" title={movie.title} />
          )}
        </div>

        <div className="flex flex-col justify-end">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
            {genres}
          </p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-white sm:text-5xl lg:text-6xl">
            {movie.title}
          </h1>
          <div className="mt-5 flex flex-wrap gap-3 text-sm text-zinc-300">
            {movie.year ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">{movie.year}</span>
            ) : null}
            {movie.duration ? (
              <span className="rounded-full bg-zinc-900 px-3 py-1">
                {t('movieDetails.durationMinutes', { duration: movie.duration })}
              </span>
            ) : null}
            {movie.rating ? (
              <span className="rounded-full bg-amber-400/15 px-3 py-1 font-semibold text-amber-300">
                {t('common.imdb')} {movie.rating}
              </span>
            ) : null}
            <span className="rounded-full bg-zinc-900 px-3 py-1">
              {movie.watched ? t('movieDetails.watched') : t('movieDetails.unwatched')}
            </span>
          </div>
          {movie.summary ? (
            <p className="mt-5 max-w-3xl text-sm leading-6 text-zinc-400 sm:text-base sm:leading-7">
              {movie.summary}
            </p>
          ) : (
            <p className="mt-5 max-w-3xl text-sm leading-6 text-zinc-600 sm:text-base sm:leading-7">
              {t('movieDetails.noSummary')}
            </p>
          )}
          {movie.watched ? (
            <div className="mt-5">
              <button
                className="rounded-lg border border-zinc-700 px-4 py-2 text-sm font-semibold text-zinc-200 transition hover:border-red-400 hover:text-white disabled:cursor-not-allowed disabled:opacity-60"
                type="button"
                disabled={isUpdatingWatchStatus}
                onClick={handleMarkUnwatched}
              >
                {isUpdatingWatchStatus
                  ? t('movieDetails.updatingWatchStatus')
                  : t('movieDetails.markUnwatched')}
              </button>
            </div>
          ) : null}
          {watchStatusError ? (
            <p className="mt-3 text-sm text-red-300">{watchStatusError}</p>
          ) : null}
        </div>
      </section>

      <section className="grid items-start gap-6 lg:grid-cols-[1fr_360px]">
        <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-black">
          {playback.playlistUrl ? (
            <HlsPlayer
              src={playback.playlistUrl}
              authToken={playback.authToken}
              poster={movie.coverUrl}
              onStatus={playback.handlePlayerStatus}
              onError={playback.handlePlayerError}
              onTimeUpdate={playback.handleTimeUpdate}
              onNativeTracks={setNativeTracks}
              nativeAudioIndex={isVod ? nativeAudioIndex : undefined}
              nativeSubtitleIndex={isVod ? nativeSubtitleIndex : undefined}
              extraTracks={extraTracks}
            />
          ) : (
            <div className="flex aspect-video items-center justify-center bg-[radial-gradient(circle_at_center,_rgba(239,68,68,0.16),_rgba(9,9,11,0.96)_48%,_#000_100%)]">
              <div className="max-w-md px-6 text-center">
                <div className="mx-auto grid h-20 w-20 place-items-center rounded-full border border-red-400/40 bg-red-500/15 text-3xl text-white shadow-[0_0_60px_rgba(239,68,68,0.25)]">
                  ▶
                </div>
                <p className="text-sm font-semibold uppercase tracking-[0.18em] text-red-400">
                  {t('movieDetails.player')}
                </p>
                <p className="mt-3 text-2xl font-semibold text-white">{mediaStateLabel}</p>
                {isDownloading ? (
                  <div className="mt-4">
                    <div className="h-2 w-full overflow-hidden rounded-full bg-zinc-800">
                      <div
                        className="h-full rounded-full bg-red-500 transition-all"
                        style={{ width: `${playback.progress.percent}%` }}
                      />
                    </div>
                    <p className="mt-2 text-xs text-zinc-400">
                      {t('movieDetails.downloadProgress', {
                        percent: playback.progress.percent,
                        downloaded: formatBytes(playback.progress.bytesDownloaded),
                        total: formatBytes(playback.progress.bytesTotal),
                      })}
                    </p>
                  </div>
                ) : (
                  <p className="mt-2 text-sm leading-6 text-zinc-500">
                    {playback.status === 'error' && playback.errorMessage
                      ? playback.errorMessage
                      : t('movieDetails.streamPlaceholder')}
                  </p>
                )}
                {playback.warnings.length > 0 ? (
                  <p className="mt-3 text-xs text-amber-300">{playback.warnings[0].message}</p>
                ) : null}
                <button
                  className="mt-6 rounded-xl bg-red-500 px-5 py-3 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-70"
                  type="button"
                  disabled={isPreparing}
                  onClick={handlePreparePlayback}
                >
                  {isPreparing
                    ? t('movieDetails.preparingPlayback')
                    : t('movieDetails.preparePlayback')}
                </button>
              </div>
            </div>
          )}

          {playback.playlistUrl ? (
            <div className="space-y-3 border-t border-zinc-900 bg-zinc-950 p-4">
              {canSeekTimeline ? (
                <div>
                  <input
                    className="w-full accent-red-500"
                    type="range"
                    min={0}
                    max={timelineMax}
                    step={1}
                    value={timelineValue}
                    onChange={(event) => setScrubSeconds(Number(event.target.value))}
                    onMouseUp={commitSeek}
                    onTouchEnd={commitSeek}
                    onKeyUp={commitSeek}
                    aria-label={t('movieDetails.seek')}
                  />
                  <div className="flex justify-between text-xs text-zinc-500">
                    <span>{formatClock(timelineValue)}</span>
                    <span>{formatClock(timelineMax)}</span>
                  </div>
                </div>
              ) : null}
              {showProgress ? (
                <div>
                  <div className="h-1.5 w-full overflow-hidden rounded-full bg-zinc-800">
                    <div
                      className="h-full rounded-full bg-red-500 transition-all"
                      style={{ width: `${playback.progress.percent}%` }}
                    />
                  </div>
                  <p className="mt-2 text-xs text-zinc-500">
                    {t('movieDetails.downloadProgress', {
                      percent: playback.progress.percent,
                      downloaded: formatBytes(playback.progress.bytesDownloaded),
                      total: formatBytes(playback.progress.bytesTotal),
                    })}
                  </p>
                </div>
              ) : null}
              <div className="flex flex-wrap gap-4">
                {audioOptions.length > 0 ? (
                  <label className="flex items-center gap-2 text-xs text-zinc-400">
                    <span className="font-semibold uppercase tracking-[0.16em]">
                      {t('movieDetails.audioTrack')}
                    </span>
                    <select
                      className="rounded-lg border border-zinc-700 bg-zinc-900 px-2 py-1 text-sm text-white"
                      value={selectedAudioValue ?? ''}
                      onChange={handleAudioChange}
                    >
                      {audioOptions.map((track) => (
                        <option key={track.index} value={track.index}>
                          {track.label}
                        </option>
                      ))}
                    </select>
                  </label>
                ) : null}
                {streamSubtitleOptions.length > 0 ? (
                  <label className="flex items-center gap-2 text-xs text-zinc-400">
                    <span className="font-semibold uppercase tracking-[0.16em]">
                      {t('movieDetails.embeddedSubtitle')}
                    </span>
                    <select
                      className="rounded-lg border border-zinc-700 bg-zinc-900 px-2 py-1 text-sm text-white"
                      value={
                        selectedStreamSubtitleValue === null ||
                        selectedStreamSubtitleValue === undefined ||
                        selectedStreamSubtitleValue === -1
                          ? ''
                          : selectedStreamSubtitleValue
                      }
                      onChange={handleStreamSubtitleChange}
                    >
                      <option value="">{t('movieDetails.subtitlesOff')}</option>
                      {streamSubtitleOptions.map((track) => (
                        <option key={track.index} value={track.index}>
                          {track.label}
                        </option>
                      ))}
                    </select>
                  </label>
                ) : null}
              </div>
            </div>
          ) : null}
        </div>

        <aside className="space-y-4">
          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">{t('movieDetails.metadata')}</h2>
            <dl className="mt-4 space-y-3 text-sm">
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('movieDetails.movieId')}</dt>
                <dd className="font-medium text-white">#{movie.id}</dd>
              </div>
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('movieDetails.year')}</dt>
                <dd className="font-medium text-white">
                  {movie.year || t('movieDetails.unknown')}
                </dd>
              </div>
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('movieDetails.length')}</dt>
                <dd className="font-medium text-white">
                  {movie.duration
                    ? t('movieDetails.durationMinutes', { duration: movie.duration })
                    : t('movieDetails.unknownLength')}
                </dd>
              </div>
              <div className="flex items-center justify-between gap-4">
                <dt className="text-zinc-500">{t('common.imdb')}</dt>
                <dd className="font-medium text-white">
                  {movie.rating || t('movieDetails.notAvailable')}
                </dd>
              </div>
            </dl>
          </div>

          {movie.genres.length > 0 ? (
            <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
              <h2 className="text-lg font-semibold text-white">{t('movieDetails.genres')}</h2>
              <div className="mt-4 flex flex-wrap gap-2">
                {movie.genres.map((genre) => (
                  <span
                    className="rounded-full bg-zinc-950 px-3 py-1 text-sm text-zinc-300"
                    key={genre}
                  >
                    {genre}
                  </span>
                ))}
              </div>
            </div>
          ) : null}

          {hasCredits ? (
            <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
              <h2 className="text-lg font-semibold text-white">{t('movieDetails.credits')}</h2>
              <dl className="mt-4 space-y-3 text-sm">
                {movie.director ? (
                  <div className="flex items-start justify-between gap-4">
                    <dt className="text-zinc-500">{t('movieDetails.director')}</dt>
                    <dd className="text-right font-medium text-white">{movie.director}</dd>
                  </div>
                ) : null}
                {movie.producers.length > 0 ? (
                  <div className="flex items-start justify-between gap-4">
                    <dt className="text-zinc-500">{t('movieDetails.producers')}</dt>
                    <dd className="text-right font-medium text-white">
                      {movie.producers.join(', ')}
                    </dd>
                  </div>
                ) : null}
              </dl>

              {movie.cast.length > 0 ? (
                <div className="mt-5">
                  <h3 className="text-sm font-semibold uppercase tracking-[0.16em] text-zinc-500">
                    {t('movieDetails.cast')}
                  </h3>
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    {movie.cast.slice(0, 8).map((member) => (
                      <div
                        className="rounded-xl border border-zinc-800 bg-zinc-950 p-3"
                        key={`${member.name}-${member.character || 'cast'}`}
                      >
                        <p className="line-clamp-1 text-sm font-semibold text-white">
                          {member.name}
                        </p>
                        {member.character ? (
                          <p className="mt-1 line-clamp-1 text-xs text-zinc-500">
                            {member.character}
                          </p>
                        ) : null}
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}
            </div>
          ) : null}

          <div className="rounded-2xl border border-zinc-800 bg-zinc-900/70 p-5">
            <h2 className="text-lg font-semibold text-white">
              {t('movieDetails.subtitles')}
            </h2>
            {osLanguages.length > 0 ? (
              <div className="mt-4 space-y-3">
                <p className="text-sm text-zinc-400">{t('movieDetails.openSubtitlesHint')}</p>
                <select
                  className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-white"
                  value={osLanguage}
                  onChange={(event) => setOsLanguage(event.target.value)}
                >
                  <option value="">{t('movieDetails.subtitlesOff')}</option>
                  {osLanguages.map((language) => (
                    <option key={language} value={language}>
                      {language}
                    </option>
                  ))}
                </select>
              </div>
            ) : (
              <p className="mt-4 text-sm text-zinc-500">{t('movieDetails.noSubtitles')}</p>
            )}
          </div>
        </aside>
      </section>

      <MovieComments
        movieId={movie.id}
        initialCount={movie.commentsCount}
      />
    </section>
  )
}

export default MovieDetailsPage
