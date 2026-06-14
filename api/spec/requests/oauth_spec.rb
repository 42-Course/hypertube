require "swagger_helper"

# Documents the OAuth2 "Resource Owner Password Credentials" flow that the
# frontend uses to exchange a username + password for an access token, plus
# token revocation. These are served by Doorkeeper (see config/initializers/
# doorkeeper.rb), not by an app controller.
RSpec.describe "OAuth", type: :request do
  let(:application) { create(:doorkeeper_application) }
  let(:user)        { create(:user, password: "Password1!") }

  path "/oauth/token" do
    post "Obtain an access token" do
      tags     "Authentication"
      security [] # public this is how a client first authenticates
      consumes "application/json"
      produces "application/json"
      description <<~DESC
        Exchange credentials for an access token using the OAuth2
        Resource Owner Password Credentials grant.

        Send `grant_type=password` together with the user's `username`
        (their username **or** email) and `password`, plus the
        `client_id`/`client_secret` of a registered OAuth application.

        If you are curious, these are the different grant types:
        `https://github.com/doorkeeper-gem/doorkeeper/blob/main/lib/doorkeeper/grant_flow.rb`

        The response contains an `access_token` to be sent as
        `Authorization: Bearer <token>` on subsequent requests.
      DESC
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[grant_type client_id client_secret],
        properties: {
          grant_type:    { type: :string, example: "password" },
          username:      { type: :string, example: "ada_l",
                           description: "Username or email of the user" },
          password:      { type: :string, example: "Password1!" },
          client_id:     { type: :string, example: "the-application-uid" },
          client_secret: { type: :string, example: "the-application-secret" }
        }
      }

      response "200", "token issued" do
        let(:body) do
          { grant_type: "password", username: user.username, password: "Password1!",
            client_id: application.uid, client_secret: application.secret }
        end
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("access_token")
          expect(data["token_type"]).to eq("Bearer")
        end
      end

      response "400", "invalid credentials" do
        let(:body) do
          { grant_type: "password", username: user.username, password: "wrong",
            client_id: application.uid, client_secret: application.secret }
        end
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to eq("invalid_grant")
        end
      end
    end
  end

  path "/oauth/revoke" do
    post "Revoke an access token" do
      tags     "Authentication"
      security []
      consumes "application/json"
      produces "application/json"
      description "Revoke a previously issued access token. Used on logout."
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[token client_id client_secret],
        properties: {
          token:         { type: :string },
          client_id:     { type: :string },
          client_secret: { type: :string }
        }
      }

      response "200", "token revoked" do
        let(:token) do
          create(:doorkeeper_access_token, application: application,
                                           resource_owner_id: user.id)
        end
        let(:body) do
          { token: token.token, client_id: application.uid,
            client_secret: application.secret }
        end
        run_test!
      end
    end
  end
end
