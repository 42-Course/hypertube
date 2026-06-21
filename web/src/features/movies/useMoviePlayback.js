import { useCallback, useEffect, useRef, useState } from 'react'
import { requestStreamTicket } from './streamingApi'
import { createStreamingClient } from './streamingClient'

const POLL_INTERVAL_MS = 1500
const METADATA_TIMEOUT_MS = 60000
const PLAYLIST_TIMEOUT_MS = 120000

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function firstPlayableVideo(files) {
  return (files || []).find((file) => file.kind === 'video' && file.supported !== false)
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
//   ticket -> wait for metadata/video file -> start session -> wait for playlist.
// Exposes the resulting status, playlist URL and the auth token the player uses.
export function useMoviePlayback(movieId) {
  const [status, setStatus] = useState('idle')
  const [playlistUrl, setPlaylistUrl] = useState(null)
  const [authToken, setAuthToken] = useState(null)
  const [errorMessage, setErrorMessage] = useState(null)
  const controlRef = useRef(null)

  const stop = useCallback(() => {
    if (controlRef.current) {
      controlRef.current.cancelled = true
    }
    controlRef.current = null
  }, [])

  // Cancel any in-flight orchestration when the movie changes or we unmount.
  useEffect(() => stop, [movieId, stop])

  const start = useCallback(async () => {
    stop()
    const control = { cancelled: false }
    controlRef.current = control
    setStatus('preparing')
    setPlaylistUrl(null)
    setErrorMessage(null)
    setAuthToken(null)

    try {
      const { ticket, mediaId, streamingUrl } = await requestStreamTicket(movieId)
      if (control.cancelled) {
        return
      }
      if (!ticket || !mediaId || !streamingUrl) {
        setStatus('error')
        setErrorMessage('Streaming is not configured.')
        return
      }
      setAuthToken(ticket)
      const client = createStreamingClient({ baseUrl: streamingUrl, ticket, mediaId })

      // 1. Wait for torrent metadata and a supported video file.
      const file = await pollUntil({
        control,
        timeoutMs: METADATA_TIMEOUT_MS,
        fn: () => client.status(),
        done: (state) => {
          if (state.state === 'failed') {
            throw new Error('The torrent failed to load.')
          }
          return firstPlayableVideo(state.files) || null
        },
      })

      // 2. Start an interactive transcode session for that file.
      if (control.cancelled) {
        return
      }
      setStatus('buffering')
      await client.play({ fileIndex: file.index, startTimeSeconds: 0 })

      // 3. Wait for an attachable HLS playlist, then hand it to the player.
      const playlist = await pollUntil({
        control,
        timeoutMs: PLAYLIST_TIMEOUT_MS,
        fn: () => client.activePlaylist(),
        done: (payload) => (payload.playlist_url ? payload : null),
      })
      if (control.cancelled) {
        return
      }
      setPlaylistUrl(client.hlsUrl(playlist.playlist_url))
    } catch (error) {
      if (!control.cancelled) {
        setStatus('error')
        setErrorMessage(error.message)
      }
    }
  }, [movieId, stop])

  const handlePlayerStatus = useCallback((playerStatus) => {
    setStatus(playerStatus === 'loading' ? 'buffering' : playerStatus)
  }, [])

  const handlePlayerError = useCallback(() => {
    setStatus('error')
  }, [])

  return {
    status,
    playlistUrl,
    authToken,
    errorMessage,
    start,
    stop,
    handlePlayerStatus,
    handlePlayerError,
  }
}
