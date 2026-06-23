import { useCallback, useEffect, useRef, useState } from 'react'
import { requestStreamTicket } from './streamingApi'
import { createStreamingClient } from './streamingClient'

const POLL_INTERVAL_MS = 1500
const METADATA_TIMEOUT_MS = 60000
const PLAYLIST_TIMEOUT_MS = 120000
const MAX_FALLBACK_RETRIES = 2

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function firstPlayableVideo(files) {
  return (files || []).find((file) => file.kind === 'video' && file.supported !== false)
}

function progressFrom(state) {
  const progress = state?.video_progress || {}
  const downloaded = Number(progress.bytes_downloaded) || 0
  const total = Number(progress.bytes_total) || 0
  const complete = total > 0 && downloaded >= total
  // Floor so a value like 99.6% never rounds up to a misleading 100% while bytes
  // are still arriving; only a genuinely complete file reports 100%.
  const percent = total > 0 ? (complete ? 100 : Math.min(99, Math.floor((downloaded / total) * 100))) : 0
  return { bytesDownloaded: downloaded, bytesTotal: total, percent, complete }
}

// Poll `fn` until `done(result)` returns a truthy value (which is returned), or
// the deadline passes, or the run is cancelled. `done` may throw to fail fast.
async function pollUntil({ control, fn, done, timeoutMs }) {
  const deadline = Date.now() + timeoutMs
  for (;;) {
    if (control.cancelled) {
      throw new Error('cancelled')
    }
    const outcome = done(await fn())
    if (outcome) {
      return outcome
    }
    if (Date.now() > deadline) {
      throw new Error('Timed out waiting for the stream.')
    }
    await sleep(POLL_INTERVAL_MS)
  }
}

// Drives the full browser playback flow against the streaming service:
//   ticket -> (VOD shortcut | wait for metadata/video file -> start session)
//          -> wait for playlist.
// Exposes status, playlist URL, live download progress, audio/subtitle tracks,
// and the auth token the player uses. Critically, it STOPS the streaming
// session when the viewer leaves (stop()/unmount/pagehide) so the per-session
// ffmpeg transcode is killed instead of pegging server CPU forever.
export function useMoviePlayback(movieId, { onPlaybackStarted } = {}) {
  const [status, setStatus] = useState('idle')
  const [playlistUrl, setPlaylistUrl] = useState(null)
  const [authToken, setAuthToken] = useState(null)
  const [errorMessage, setErrorMessage] = useState(null)
  const [snapshot, setSnapshot] = useState(null)
  const [mode, setMode] = useState(null)
  // Global movie timeline: an interactive HLS session starts at 0 but represents
  // `sessionStartSeconds` into the movie, so absolute position = start + videoTime.
  const [sessionStartSeconds, setSessionStartSeconds] = useState(0)
  const [videoTime, setVideoTime] = useState(0)
  const controlRef = useRef(null)
  const currentTimeRef = useRef(0)
  const startRef = useRef(null)
  const startedCallbackRef = useRef(onPlaybackStarted)

  useEffect(() => {
    startedCallbackRef.current = onPlaybackStarted
  }, [onPlaybackStarted])

  // Tell the streaming service to tear down the active session (kills ffmpeg).
  const stopServerSession = useCallback((control) => {
    if (!control?.client || !control.sessionId) {
      return
    }
    control.client.stopSession(control.sessionId).catch(() => {})
  }, [])

  const stop = useCallback(() => {
    const control = controlRef.current
    if (control) {
      control.cancelled = true
      if (control.pollTimer) {
        clearTimeout(control.pollTimer)
      }
      stopServerSession(control)
      // Pause the torrent too when leaving an interactive (still-downloading)
      // movie, so it only downloads while someone is watching. VOD playback has
      // no session and nothing left to download, so it is left alone.
      if (control.client && control.mode === 'interactive') {
        control.client.pauseMedia().catch(() => {})
      }
    }
    controlRef.current = null
  }, [stopServerSession])

  const notifyStarted = useCallback((control) => {
    if (control.startedNotified) {
      return
    }
    control.startedNotified = true
    try {
      startedCallbackRef.current?.()
    } catch {
      // The watched-status update is best-effort; never break playback.
    }
  }, [])

  // Re-acquire the stream from scratch (treat a failed/missing file as "no file"
  // and fall back to the torrent flow), capped to avoid retry loops.
  const maybeFallback = useCallback((control, error) => {
    if (control.cancelled) {
      return
    }
    if (control.retries >= MAX_FALLBACK_RETRIES) {
      setStatus('error')
      setErrorMessage(error?.message || 'Playback failed.')
      return
    }
    setStatus('preparing')
    setPlaylistUrl(null)
    startRef.current?.()
  }, [])

  // Long-lived status poll: keeps download %, tracks, and warnings fresh for the
  // whole time a media is loaded, and triggers a retry if the media fails.
  const runStatusPoll = useCallback((control) => {
    const tick = async () => {
      if (control.cancelled || controlRef.current !== control) {
        return
      }
      try {
        const state = await control.client.status()
        if (control.cancelled) {
          return
        }
        setSnapshot(state)
        if (state.state === 'failed' && !control.recovering) {
          control.recovering = true
          maybeFallback(control, new Error('The media failed to prepare.'))
          return
        }
      } catch {
        // Transient poll failure; keep trying.
      }
      if (!control.cancelled && controlRef.current === control) {
        control.pollTimer = setTimeout(tick, POLL_INTERVAL_MS)
      }
    }
    tick()
  }, [maybeFallback])

  const start = useCallback(async () => {
    const previousRetries = controlRef.current?.retries || 0
    stop()
    const control = {
      cancelled: false,
      client: null,
      sessionId: null,
      sessionStart: 0,
      mode: null,
      retries: previousRetries,
      startedNotified: false,
      recovering: false,
      pollTimer: null,
    }
    controlRef.current = control
    currentTimeRef.current = 0
    setStatus('preparing')
    setPlaylistUrl(null)
    setErrorMessage(null)
    setAuthToken(null)
    setMode(null)
    setSessionStartSeconds(0)
    setVideoTime(0)

    try {
      const { ticket, mediaId, streamingUrl } = await requestStreamTicket(movieId)
      if (control.cancelled) {
        return false
      }
      if (!ticket || !mediaId || !streamingUrl) {
        setStatus('error')
        setErrorMessage('Streaming is not configured.')
        return false
      }
      setAuthToken(ticket)
      const client = createStreamingClient({ baseUrl: streamingUrl, ticket, mediaId })
      control.client = client
      runStatusPoll(control)

      // 1. Wait for torrent metadata and a supported video file (also yields the
      //    first status snapshot, which reveals whether a VOD is already ready).
      const resolved = await pollUntil({
        control,
        timeoutMs: METADATA_TIMEOUT_MS,
        fn: () => client.status(),
        done: (current) => {
          if (current.state === 'failed') {
            throw new Error('The torrent failed to load.')
          }
          if (current.vod?.ready && current.vod.playlist_url) {
            return { vodPlaylistUrl: current.vod.playlist_url }
          }
          const file = firstPlayableVideo(current.files)
          return file ? { file } : null
        },
      })
      if (control.cancelled) {
        return false
      }

      // 2a. VOD-first: a fully-downloaded movie has a static HLS master playlist
      //     with every audio/subtitle rendition. No per-viewer ffmpeg is spawned.
      if (resolved.vodPlaylistUrl) {
        control.mode = 'vod'
        setMode('vod')
        notifyStarted(control)
        setStatus('buffering')
        setPlaylistUrl(client.hlsUrl(resolved.vodPlaylistUrl))
        return true
      }

      // 2b. Interactive: start a transcode session for the selected file.
      control.mode = 'interactive'
      setMode('interactive')
      setStatus('buffering')
      notifyStarted(control)
      const session = await client.play({ fileIndex: resolved.file.index, startTimeSeconds: 0 })
      control.sessionId = session.session_id

      // 3. Wait for an attachable HLS playlist, then hand it to the player.
      const playlist = await pollUntil({
        control,
        timeoutMs: PLAYLIST_TIMEOUT_MS,
        fn: () => client.activePlaylist(),
        done: (payload) => (payload.playlist_url ? payload : null),
      })
      if (control.cancelled) {
        return false
      }
      control.sessionId = playlist.session_id || control.sessionId
      control.sessionStart = playlist.session_start_time_seconds || 0
      setSessionStartSeconds(control.sessionStart)
      setVideoTime(0)
      setPlaylistUrl(client.hlsUrl(playlist.playlist_url))
      return true
    } catch (error) {
      if (!control.cancelled) {
        setStatus('error')
        setErrorMessage(error.message)
      }
      return false
    }
  }, [movieId, stop, runStatusPoll, notifyStarted])

  useEffect(() => {
    startRef.current = start
  }, [start])

  // Seek an interactive session to an absolute movie position (in seconds). The
  // streaming service starts a new transcode there and the range-server
  // prioritizes the pieces around that point, so the user can jump ahead even
  // before the whole torrent has downloaded. Optional track changes ride along.
  const performSeek = useCallback(async (targetSeconds, opts = {}) => {
    const control = controlRef.current
    if (!control || control.mode !== 'interactive' || !control.client) {
      return
    }
    const client = control.client
    const target = Math.max(0, Number(targetSeconds) || 0)
    setStatus('buffering')
    try {
      const session = await client.seek({
        targetSeconds: target,
        selectedAudio: opts.selectedAudio,
        selectedSubtitle: opts.selectedSubtitle,
      })
      if (control.cancelled) {
        return
      }
      control.sessionId = session.session_id || control.sessionId
      const playlist = await pollUntil({
        control,
        timeoutMs: PLAYLIST_TIMEOUT_MS,
        fn: () => client.activePlaylist(),
        done: (payload) =>
          payload.playlist_url && (!session.session_id || payload.session_id === session.session_id)
            ? payload
            : null,
      })
      if (control.cancelled) {
        return
      }
      control.sessionId = playlist.session_id || control.sessionId
      control.sessionStart = playlist.session_start_time_seconds ?? target
      setSessionStartSeconds(control.sessionStart)
      setVideoTime(0)
      setPlaylistUrl(client.hlsUrl(playlist.playlist_url))
    } catch (error) {
      if (!control.cancelled) {
        setErrorMessage(error.message)
      }
    }
  }, [])

  // Track changes re-seek to the CURRENT position; the global timeline bar seeks
  // to an arbitrary one.
  const switchTrack = useCallback(
    (opts) => {
      const control = controlRef.current
      const globalTime = (control?.sessionStart || 0) + (currentTimeRef.current || 0)
      return performSeek(globalTime, opts)
    },
    [performSeek],
  )

  const seekTo = useCallback((targetSeconds) => performSeek(targetSeconds, {}), [performSeek])

  const selectAudio = useCallback((index) => switchTrack({ selectedAudio: index }), [switchTrack])
  const selectStreamSubtitle = useCallback(
    (index) => switchTrack({ selectedSubtitle: index === null || index === undefined ? null : index }),
    [switchTrack],
  )

  // Cancel orchestration AND stop the server session when the movie changes or
  // we unmount. Also stop on pagehide (tab close / navigation) via a beacon,
  // since React cleanup may not run on a hard unload.
  useEffect(() => {
    const handlePageHide = () => {
      const control = controlRef.current
      if (!control?.client) {
        return
      }
      if (control.sessionId) {
        control.client.stopSessionBeacon(control.sessionId)
      }
      if (control.mode === 'interactive') {
        control.client.pauseMediaBeacon()
      }
    }
    window.addEventListener('pagehide', handlePageHide)
    return () => {
      window.removeEventListener('pagehide', handlePageHide)
      stop()
    }
  }, [movieId, stop])

  const handlePlayerStatus = useCallback((playerStatus) => {
    if (playerStatus === 'loading') {
      setStatus('buffering')
    } else if (playerStatus === 'ready') {
      setStatus('playing')
    } else {
      setStatus(playerStatus)
    }
  }, [])

  const handlePlayerError = useCallback(() => {
    const control = controlRef.current
    // A playback error (e.g. a VOD file went missing) is treated as "no file":
    // re-acquire the stream from scratch, falling back to the torrent flow.
    if (control && control.retries < MAX_FALLBACK_RETRIES) {
      control.retries += 1
      maybeFallback(control, new Error('Playback failed; retrying.'))
      return
    }
    setStatus('error')
  }, [maybeFallback])

  const handleTimeUpdate = useCallback((currentTime) => {
    const time = Number(currentTime) || 0
    currentTimeRef.current = time
    setVideoTime(time)
  }, [])

  const progress = progressFrom(snapshot)

  return {
    status,
    mode,
    playlistUrl,
    authToken,
    errorMessage,
    start,
    stop,
    handlePlayerStatus,
    handlePlayerError,
    handleTimeUpdate,
    // Live media snapshot for the UI.
    mediaState: snapshot?.state || null,
    progress,
    durationSeconds: snapshot?.duration_seconds ?? null,
    audioTracks: snapshot?.audio_tracks || [],
    streamSubtitles: snapshot?.subtitles || [],
    selectedAudio: snapshot?.playback?.selected_audio ?? null,
    selectedStreamSubtitle: snapshot?.playback?.selected_subtitle ?? null,
    warnings: snapshot?.warnings || [],
    streamErrors: snapshot?.errors || [],
    vodReady: Boolean(snapshot?.vod?.ready),
    selectAudio,
    selectStreamSubtitle,
    // Global movie timeline (interactive sessions): absolute current position and
    // a seek that can jump anywhere in the movie, even before it has downloaded.
    globalTime: sessionStartSeconds + videoTime,
    seekTo,
  }
}
