# frozen_string_literal: true

# Handles the OmniAuth provider callbacks (42 + Google).
#
# This is a browser-facing redirect endpoint, not part of the JSON API, so it
# is a full ActionController (cookies/session) rather than ActionController::API.
# On success it provisions/finds the user, mints a Doorkeeper access token, and
# redirects back to the SPA with the token in the URL fragment (kept out of
# server access logs and never sent back to the server).
class Users::OmniauthCallbacksController < ActionController::Base
  skip_forgery_protection

  # Devise maps /users/auth/:provider/callback to an action named after the
  # provider. Both providers share the same handling.
  def google_oauth2 = handle_callback
  def fortytwo      = handle_callback

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

  # Mint a token tied to the trusted first-party application so the SPA can
  # immediately call the API as the authenticated user.
  def issue_access_token(user)
    Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id,
      application_id:    first_party_application.id,
      scopes:            "",
      expires_in:        2.hours,
      use_refresh_token: false
    )
  end

  def first_party_application
    Doorkeeper::Application.find_or_create_by!(name: "Hypertube Web") do |app|
      app.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
      app.confidential = false
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
