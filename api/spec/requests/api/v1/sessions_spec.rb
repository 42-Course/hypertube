require "swagger_helper"

RSpec.describe "Sessions API", type: :request do
  let(:user) { create(:user, email: "login@example.com", username: "loginuser", password: "Password1!") }

  path "/api/v1/session" do
    post "Log in with email/username + password" do
      tags     "Authentication"
      security []
      consumes "application/json"
      produces "application/json"
      description "Exchanges credentials for a first-party access token. Unlike " \
                  "POST /oauth/token, this requires no client_id or client_secret " \
                  "the SPA is a trusted first-party client and the token is minted " \
                  "server-side. Use the returned access_token as a Bearer token."
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[login password],
        properties: {
          login:    { type: :string, description: "Email or username", example: "login@example.com" },
          password: { type: :string, example: "Password1!" }
        }
      }

      response "201", "authenticated returns an access token" do
        let(:body) { { login: user.email, password: "Password1!" } }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["access_token"]).to be_present
          expect(data["token_type"]).to eq("Bearer")
          expect(data["expires_in"]).to be_positive
          expect(data.dig("user", "username")).to eq(user.username)
        end
      end

      response "201", "also accepts the username as the login" do
        let(:body) { { login: user.username, password: "Password1!" } }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["access_token"]).to be_present
        end
      end

      response "401", "wrong password" do
        let(:body) { { login: user.email, password: "wrong" } }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("error")
        end
      end

      response "401", "unknown account (same response, no enumeration)" do
        let(:body) { { login: "nobody@example.com", password: "Password1!" } }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("error")
        end
      end
    end

    delete "Log out (revoke the current access token)" do
      tags     "Authentication"
      security [ { oauth2: [] } ]
      produces "application/json"
      description "Revokes the access token presented in the Authorization header."

      let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
      let(:Authorization) { "Bearer #{token.token}" }

      response "204", "token revoked" do
        run_test! do
          expect(token.reload.revoked?).to be(true)
        end
      end

      response "401", "unauthorized no token" do
        let(:Authorization) { nil }
        run_test!
      end
    end
  end
end
