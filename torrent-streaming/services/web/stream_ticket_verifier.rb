# frozen_string_literal: true

require "jwt"
require "securerandom"

# Verifies stream tickets minted by the Hypertube API.
#
# This is the streaming-service half of the API's StreamTicket contract: same
# algorithm, issuer, audience and shared secret (STREAM_TICKET_SECRET). It lets
# the streaming service authorize a viewer for a single movie -- locally, with
# no callback to the API per HLS request -- before serving any playlist or
# segment.
#
# Wiring (next step): in the web app, require this file and gate the stream
# routes, e.g.
#
#   claims = StreamTicketVerifier.verify(params[:ticket])
#   halt 403 unless claims["movie_id"].to_s == requested_movie_id
#   user_id = claims["sub"]
#
module StreamTicketVerifier
  ALGORITHM     = "HS256"
  ISSUER        = "hypertube-api"
  AUDIENCE      = "hypertube-streaming"
  STREAM_SCOPE  = "stream"   # viewer ticket: a user may watch one movie
  SERVICE_SCOPE = "service"  # machine-to-machine: the API orchestrating media

  Error = Class.new(StandardError)

  module_function

  # Verify a token and return its claims (Hash), or raise
  # StreamTicketVerifier::Error for any invalid/expired/forged/mis-scoped token.
  # `scope` selects which kind of token is acceptable (viewer vs service).
  def verify(token, scope: STREAM_SCOPE)
    claims, = JWT.decode(
      token.to_s, secret, true,
      algorithm:  ALGORITHM,
      iss:        ISSUER,
      verify_iss: true,
      aud:        AUDIENCE,
      verify_aud: true
    )

    unless claims["scope"] == scope
      raise Error, "unexpected scope: #{claims['scope'].inspect}"
    end

    claims
  rescue JWT::DecodeError => e
    raise Error, e.message
  end

  # Mint a short-lived service-scope token the streaming service uses to call
  # back into the Hypertube API (e.g. download-complete). It rides the same
  # shared-secret contract, so the API's StreamTicket.verify accepts it.
  def issue_service_token(ttl: 60)
    now = Time.now.to_i
    JWT.encode(
      {
        iss:   ISSUER,
        aud:   AUDIENCE,
        scope: SERVICE_SCOPE,
        iat:   now,
        exp:   now + ttl,
        jti:   SecureRandom.uuid
      },
      secret,
      ALGORITHM
    )
  end

  def secret
    value = ENV["STREAM_TICKET_SECRET"].to_s
    raise Error, "STREAM_TICKET_SECRET is not configured" if value.empty?

    value
  end
end
