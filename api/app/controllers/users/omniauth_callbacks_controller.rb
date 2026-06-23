# frozen_string_literal: true

# Handles the OmniAuth provider callbacks (42 + Google + GitHub + Microsoft).
#
# This is a browser-facing redirect endpoint, not part of the JSON API, so it
# is a full ActionController (cookies/session) rather than ActionController::API.
# On success it provisions/finds the user, mints a Doorkeeper access token, and
# redirects back to the SPA with the token in the URL fragment (kept out of
# server access logs and never sent back to the server).
class Users::OmniauthCallbacksController < ActionController::Base
  include FirstPartyTokens

  skip_forgery_protection

  # Devise maps /users/auth/:provider/callback to an action named after the
  # provider. All providers share the same handling.
  def google_oauth2 = handle_callback
  def fortytwo      = handle_callback
  def github        = handle_callback
  def microsoft     = handle_callback

  # Reached via OmniAuth.config.on_failure (bad state, denied consent, etc.).
  def failure
    redirect_to "#{frontend_url}/login?error=oauth_failed", allow_other_host: true
  end

  private

  def handle_callback
    # The OmniAuth middleware guarantees `omniauth.auth` is set by the time we
    # get here; provider/strategy failures are routed to #failure instead.
    user = User.from_omniauth(request.env["omniauth.auth"])

    if user.persisted?
      token = issue_access_token(user)
      redirect_to success_redirect_url(token), allow_other_host: true
    else
      redirect_to "#{frontend_url}/login?error=oauth_invalid", allow_other_host: true
    end
  end

  def success_redirect_url(token)
    "#{frontend_url}/auth/callback#access_token=#{token.token}" \
      "&token_type=Bearer&expires_in=#{token.expires_in}"
  end

  def frontend_url
    ENV.fetch("FRONTEND_URL", "http://localhost:5173")
  end
end
