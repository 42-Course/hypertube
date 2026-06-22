# frozen_string_literal: true

require "jwt"

# Mints and verifies short-lived, movie-scoped "stream tickets".
#
# A stream ticket is a small signed JWT the API hands to an already
# authenticated user so their browser can talk directly to the (separate)
# streaming service. The streaming service shares STREAM_TICKET_SECRET and
# verifies the signature locally, so:
#
#   * the user's first-party API access token never leaves the API boundary;
#   * the streaming service does not call back to the API on every HLS segment;
#   * the ticket only grants streaming of a single movie, for a few minutes
#     (least privilege).
#
# The streaming service mirrors #verify with the same algorithm, issuer,
# audience and secret.
class StreamTicket
  ALGORITHM     = "HS256"
  ISSUER        = "hypertube-api"
  AUDIENCE      = "hypertube-streaming"
  SCOPE         = "stream"   # viewer ticket
  SERVICE_SCOPE = "service"  # machine-to-machine (API -> streaming orchestration)
  TTL           = 5.minutes
  SERVICE_TTL   = 1.minute

  Error = Class.new(StandardError)

  class << self
    # Issue a viewer ticket binding a user to a single movie for a short window.
    # `media_id` binds the ticket to the concrete streaming media once the
    # movie->magnet handoff has resolved it, so the streaming service can reject
    # a ticket replayed against another media.
    def issue(user:, movie:, media_id: nil, ttl: TTL)
      now = Time.current
      payload = {
        iss:      ISSUER,
        aud:      AUDIENCE,
        sub:      user.id.to_s,
        movie_id: movie.id,
        scope:    SCOPE,
        iat:      now.to_i,
        exp:      (now + ttl).to_i,
        jti:      SecureRandom.uuid
      }
      payload[:media_id] = media_id if media_id
      JWT.encode(payload, secret, ALGORITHM)
    end

    # Mint a short-lived service token the API uses to authenticate itself to
    # the streaming service's orchestration endpoints (no user context).
    def service_token(ttl: SERVICE_TTL)
      now = Time.current
      JWT.encode({
        iss:   ISSUER,
        aud:   AUDIENCE,
        scope: SERVICE_SCOPE,
        iat:   now.to_i,
        exp:   (now + ttl).to_i,
        jti:   SecureRandom.uuid
      }, secret, ALGORITHM)
    end

    # Verify a ticket and return its claims, or raise StreamTicket::Error.
    # Kept here so the contract is round-trip tested in the API's own suite.
    def verify(token)
      claims, = JWT.decode(
        token.to_s, secret, true,
        algorithm:  ALGORITHM,
        iss:        ISSUER,
        verify_iss: true,
        aud:        AUDIENCE,
        verify_aud: true
      )
      claims
    rescue JWT::DecodeError => e
      raise Error, e.message
    end

    private

    def secret
      ENV["STREAM_TICKET_SECRET"].presence ||
        raise(Error, "STREAM_TICKET_SECRET is not configured")
    end
  end
end
