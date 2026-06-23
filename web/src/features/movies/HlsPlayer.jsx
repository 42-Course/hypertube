import { useEffect, useRef } from 'react'
import Hls from 'hls.js'

// Plays an HLS (.m3u8) source. Prefers native HLS where the browser supports it
// (Safari / iOS), otherwise falls back to hls.js. The `src` is expected to carry
// the stream ticket as a query param, so the streaming service authorizes both
// the playlist and every segment request without custom headers (which native
// playback cannot set).
//
// `onStatus` is called with 'loading' | 'ready' | 'error' so the page can drive
// its own UI; `onError` receives the underlying hls.js error detail. `authToken`
// (the stream ticket), when given, is sent as a Bearer header on every hls.js
// request (playlist + segments) so the streaming service authorizes them.
//
// `onTimeUpdate(currentTime)` reports playback position (used by the playback
// hook to seek to the right offset when switching tracks). `extraTracks` injects
// external subtitle `<track>`s (e.g. OpenSubtitles VTT) independent of the HLS
// stream. `onNativeTracks`/`nativeAudioIndex`/`nativeSubtitleIndex` expose and
// drive hls.js's own audio/subtitle renditions (used for VOD master playlists).
function HlsPlayer({
  src,
  poster,
  authToken,
  autoPlay = true,
  onStatus,
  onError,
  onTimeUpdate,
  extraTracks = [],
  onNativeTracks,
  nativeAudioIndex,
  nativeSubtitleIndex,
}) {
  const videoRef = useRef(null)
  const hlsRef = useRef(null)

  useEffect(() => {
    const video = videoRef.current
    if (!video || !src) {
      return undefined
    }

    onStatus?.('loading')

    const fail = (detail) => {
      onStatus?.('error')
      onError?.(detail)
    }

    const handleTimeUpdate = () => onTimeUpdate?.(video.currentTime || 0)
    video.addEventListener('timeupdate', handleTimeUpdate)

    // Native HLS: hand the URL straight to the element. It cannot set custom
    // headers, so the ticket must already be in the src (query param).
    if (video.canPlayType('application/vnd.apple.mpegurl')) {
      const handleLoaded = () => onStatus?.('ready')
      video.src = src
      video.addEventListener('loadedmetadata', handleLoaded)
      if (autoPlay) {
        video.play().catch(() => {})
      }
      return () => {
        video.removeEventListener('loadedmetadata', handleLoaded)
        video.removeEventListener('timeupdate', handleTimeUpdate)
        video.removeAttribute('src')
        video.load()
      }
    }

    if (Hls.isSupported()) {
      const hls = new Hls({
        enableWorker: true,
        lowLatencyMode: false,
        xhrSetup: authToken
          ? (xhr) => xhr.setRequestHeader('Authorization', `Bearer ${authToken}`)
          : undefined,
      })
      hlsRef.current = hls
      hls.loadSource(src)
      hls.attachMedia(video)
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        onStatus?.('ready')
        // Surface the playlist's own audio/subtitle renditions (VOD path).
        onNativeTracks?.({
          audio: (hls.audioTracks || []).map((track, index) => ({
            index,
            label: track.name || track.lang || `Audio ${index + 1}`,
            language: track.lang || null,
          })),
          subtitle: (hls.subtitleTracks || []).map((track, index) => ({
            index,
            label: track.name || track.lang || `Subtitle ${index + 1}`,
            language: track.lang || null,
          })),
        })
        if (autoPlay) {
          video.play().catch(() => {})
        }
      })
      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (data.fatal) {
          fail(data)
        }
      })
      return () => {
        video.removeEventListener('timeupdate', handleTimeUpdate)
        hls.destroy()
        hlsRef.current = null
      }
    }

    video.removeEventListener('timeupdate', handleTimeUpdate)
    fail({ type: 'unsupported' })
    return undefined
  }, [src, authToken, autoPlay, onStatus, onError, onTimeUpdate, onNativeTracks])

  // Drive hls.js native audio rendition selection (VOD master playlists).
  useEffect(() => {
    const hls = hlsRef.current
    if (hls && typeof nativeAudioIndex === 'number' && nativeAudioIndex >= 0) {
      hls.audioTrack = nativeAudioIndex
    }
  }, [nativeAudioIndex])

  // Drive hls.js native subtitle rendition selection (-1 disables).
  useEffect(() => {
    const hls = hlsRef.current
    if (hls && typeof nativeSubtitleIndex === 'number') {
      hls.subtitleTrack = nativeSubtitleIndex
      hls.subtitleDisplay = nativeSubtitleIndex >= 0
    }
  }, [nativeSubtitleIndex])

  return (
    <video
      ref={videoRef}
      className="aspect-video w-full bg-black"
      controls
      playsInline
      poster={poster || undefined}
      crossOrigin="anonymous"
    >
      {extraTracks.map((track) => (
        <track
          key={track.src}
          kind="subtitles"
          src={track.src}
          srcLang={track.srcLang || 'und'}
          label={track.label || track.srcLang || 'Subtitle'}
          default={Boolean(track.default)}
        />
      ))}
    </video>
  )
}

export default HlsPlayer
