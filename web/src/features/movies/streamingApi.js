import client from '../../api/client'

// Requests a short-lived stream ticket from the API. The API resolves the movie
// to a prepared streaming media (starting the torrent download) and returns the
// media_id plus a signed JWT bound to it. The streaming service verifies the
// ticket locally (no per-segment API round-trip), so the user's API token never
// reaches the streaming boundary.
//
// Returns { ticket, tokenType, expiresIn, mediaId, streamingUrl } where
// streamingUrl is the browser-facing base of the streaming service. Turning
// (streamingUrl + mediaId + ticket) into a playing HLS stream is the streaming
// service's playback orchestration (select file -> start session -> playlist).
export async function requestStreamTicket(movieId) {
  const { data } = await client.post(`/api/v1/movies/${movieId}/stream_ticket`)
  return {
    ticket: data.ticket,
    tokenType: data.token_type,
    expiresIn: data.expires_in,
    mediaId: data.media_id || null,
    streamingUrl: data.streaming_url || null,
  }
}
