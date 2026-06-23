import axios from 'axios'

// A thin client for the (separate) streaming service, authorized by a stream
// ticket. The ticket rides as a Bearer header on these JSON calls; the HLS
// media requests hls.js makes carry it the same way via xhrSetup (HlsPlayer).
//
// Built from the { streamingUrl, ticket, mediaId } the API returns from
// POST /movies/:id/stream_ticket.
export function createStreamingClient({ baseUrl, ticket, mediaId }) {
  const root = baseUrl.replace(/\/$/, '')
  const http = axios.create({
    baseURL: root,
    headers: { Authorization: `Bearer ${ticket}` },
    timeout: 15000,
  })

  return {
    baseUrl: root,
    mediaId,

    // Current media state: torrent metadata, file list, download progress,
    // audio/subtitle tracks, the active playback session, VOD readiness, and
    // user-facing warnings/errors.
    async status() {
      const { data } = await http.get(`/media/${mediaId}/status.json`)
      return data
    },

    // Start (or restart) an interactive playback session for a video file.
    async play({ fileIndex, startTimeSeconds = 0, selectedAudio, selectedSubtitle }) {
      const { data } = await http.post(`/media/${mediaId}/play`, {
        file_index: fileIndex,
        start_time_seconds: startTimeSeconds,
        selected_audio: selectedAudio,
        selected_subtitle: selectedSubtitle,
      })
      return data
    },

    // Seek the active session (also used to switch audio/subtitle tracks, which
    // the streaming service implements as a re-seek with the new selection).
    async seek({ targetSeconds, selectedAudio, selectedSubtitle }) {
      const body = { target_seconds: targetSeconds }
      if (selectedAudio !== undefined) {
        body.selected_audio = selectedAudio
      }
      if (selectedSubtitle !== undefined) {
        body.selected_subtitle = selectedSubtitle
      }
      const { data } = await http.post(`/media/${mediaId}/seek`, body)
      return data
    },

    // The currently-attachable playlist for the active session (or null url).
    async activePlaylist() {
      const { data } = await http.get(`/media/${mediaId}/active-playlist.json`)
      return data
    },

    // Stop a playback session, terminating its ffmpeg process group on the
    // streaming service. Critical for releasing CPU when the viewer leaves.
    async stopSession(sessionId) {
      if (!sessionId) {
        return null
      }
      const { data } = await http.post(`/sessions/${sessionId}/stop`, {})
      return data
    },

    // Best-effort stop that survives page unload. `fetch` headers don't reliably
    // flush during unload, so the ticket rides as a query param (the streaming
    // service accepts `?ticket=`) and we use keepalive. Used from pagehide.
    stopSessionBeacon(sessionId) {
      if (!sessionId) {
        return false
      }
      const url = `${root}/sessions/${encodeURIComponent(sessionId)}/stop?ticket=${encodeURIComponent(ticket)}`
      try {
        if (typeof navigator !== 'undefined' && navigator.sendBeacon) {
          return navigator.sendBeacon(url)
        }
        fetch(url, { method: 'POST', keepalive: true }).catch(() => {})
        return true
      } catch {
        return false
      }
    },

    // Pause downloading for this media (called when the viewer leaves a movie
    // that isn't fully downloaded, so the torrent only runs while watched).
    // Resuming happens server-side when playback is started again.
    async pauseMedia() {
      const { data } = await http.post(`/media/${mediaId}/pause`, {})
      return data
    },

    // Best-effort pause that survives page unload (ticket as query param).
    pauseMediaBeacon() {
      const url = `${root}/media/${encodeURIComponent(mediaId)}/pause?ticket=${encodeURIComponent(ticket)}`
      try {
        if (typeof navigator !== 'undefined' && navigator.sendBeacon) {
          return navigator.sendBeacon(url)
        }
        fetch(url, { method: 'POST', keepalive: true }).catch(() => {})
        return true
      } catch {
        return false
      }
    },

    // Turn a relative HLS path from the service into an absolute URL the player
    // can load. The ticket also rides as a query param so a native-HLS <video>
    // can authorize the initial playlist request without custom headers.
    hlsUrl(relativePath) {
      if (!relativePath) {
        return null
      }
      const separator = relativePath.includes('?') ? '&' : '?'
      return `${root}${relativePath}${separator}ticket=${encodeURIComponent(ticket)}`
    },
  }
}
