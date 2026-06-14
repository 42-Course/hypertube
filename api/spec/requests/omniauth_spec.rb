require "swagger_helper"

# Documents and exercises the OmniAuth provider-login flow (42 + Google).
# Uses OmniAuth's test mode to mock the provider so no real credentials or
# network calls are needed.
RSpec.describe "Provider login (OmniAuth)", type: :request do
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "g-1",
      info: { email: "gina@example.com", first_name: "Gina",
              last_name: "Goo", nickname: "gina_g" }
    )
    OmniAuth.config.mock_auth[:fortytwo] = OmniAuth::AuthHash.new(
      provider: "fortytwo", uid: "42-1",
      info: { email: "norm@example.com", first_name: "Norm",
              last_name: "Forty", nickname: "nforty",
              image: "https://cdn.intra.42.fr/users/norm.jpg" }
    )
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:fortytwo] = nil
  end

  path "/users/auth/{provider}" do
    parameter name: :provider, in: :path, required: true,
              schema: { type: :string, enum: %w[google_oauth2 fortytwo] },
              description: "Identity provider to authenticate with"

    get "Start provider login" do
      tags     "Authentication"
      security []
      description <<~DESC
        Point the browser here to begin login with an external provider
        (`google_oauth2` or `forty_two`). The server hands off to the provider's consent screen
        and, after approval, the provider redirects back to the callback below.

        This is a redirect endpoint meant for the browser not an XHR/JSON call.
      DESC

      response "302", "redirect to the provider" do
        let(:provider) { "google_oauth2" }
        run_test!
      end
    end
  end

  path "/users/auth/{provider}/callback" do
    parameter name: :provider, in: :path, required: true,
              schema: { type: :string, enum: %w[google_oauth2 fortytwo] }

    get "Provider OAuth2 callback" do
      tags     "Authentication"
      security []
      description <<~DESC
        The provider redirects here after the user approves access. The server
        provisions (or finds) the matching user, mints an access token, and
        redirects to `FRONTEND_URL/auth/callback#access_token=...&token_type=Bearer`.
        The SPA reads the token from the URL fragment.
      DESC

      response "302", "redirect to the SPA with an access token" do
        let(:provider) { "google_oauth2" }
        run_test! do |response|
          expect(response.headers["Location"]).to include("access_token=")
          expect(User.find_by(provider: "google_oauth2", uid: "g-1")).to be_present
        end
      end
    end
  end

  # Edge cases plain request specs (not part of the published docs).
  describe "callback edge cases" do
    it "provisions the user with the profile picture from the provider" do
      get "/users/auth/fortytwo/callback"
      user = User.find_by(provider: "fortytwo", uid: "42-1")
      expect(user.profile_picture_url).to eq("https://cdn.intra.42.fr/users/norm.jpg")
    end

    it "redirects to the SPA login with an error when the provider fails" do
      OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
      get "/users/auth/google_oauth2/callback"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("error=oauth_failed")
    end

    it "redirects with an error when the user cannot be provisioned" do
      create(:user, email: "norm@example.com") # email already taken
      get "/users/auth/fortytwo/callback"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("error=oauth_invalid")
      expect(response.headers["Location"]).not_to include("access_token=")
    end
  end
end
