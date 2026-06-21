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
function HlsPlayer({ src, poster, authToken, autoPlay = true, onStatus, onError }) {
  const videoRef = useRef(null)

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
      hls.loadSource(src)
      hls.attachMedia(video)
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        onStatus?.('ready')
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
        hls.destroy()
      }
    }

    fail({ type: 'unsupported' })
    return undefined
  }, [src, authToken, autoPlay, onStatus, onError])

  return (
    <video
      ref={videoRef}
      className="aspect-video h-full w-full bg-black"
      controls
      playsInline
      poster={poster || undefined}
    />
  )
}

export default HlsPlayer
