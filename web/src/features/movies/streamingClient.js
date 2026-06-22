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

    // Current media state: torrent metadata, file list, playback, errors.
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

    // The currently-attachable playlist for the active session (or null url).
    async activePlaylist() {
      const { data } = await http.get(`/media/${mediaId}/active-playlist.json`)
      return data
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
