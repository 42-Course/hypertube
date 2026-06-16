# frozen_string_literal: true

# Mints first-party Doorkeeper access tokens without requiring the SPA to hold
# any OAuth client credentials.
#
# Both entry points the SPA uses to log in -- the OmniAuth social callback and
# the email/password sessions endpoint -- provision the same kind of token: one
# tied to the trusted, public "Hypertube Web" application. Because that
# application is `confidential: false`, there is no client secret, and the SPA
# never needs a client_id/client_secret to obtain a token.
module FirstPartyTokens
  # The public first-party application every SPA-issued token belongs to.
  def first_party_application
    Doorkeeper::Application.find_or_create_by!(name: "Hypertube Web") do |app|
      app.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
      app.confidential = false
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
end
