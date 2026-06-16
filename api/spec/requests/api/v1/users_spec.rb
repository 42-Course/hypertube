require "swagger_helper"

RSpec.describe "Users API", type: :request do
  let(:user)  { create(:user) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:Authorization) { "Bearer #{token.token}" }

  path "/api/v1/me" do
    get "Get the current authenticated user" do
      tags     "Users"
      security [ { oauth2: [] } ]
      produces "application/json"
      description "Returns the full profile of the user the access token belongs " \
                  "to (including private fields like email)."

      response "200", "returns the current user" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["id"]).to eq(user.id)
          expect(data["username"]).to eq(user.username)
          expect(data["email"]).to eq(user.email)
          expect(data.keys).to include("first_name", "last_name", "preferred_language")
        end
      end

      response "401", "unauthorized no token" do
        let(:Authorization) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/users" do
    get "List users" do
      tags        "Users"
      security    [ { oauth2: [] } ]
      produces    "application/json"

      response "200", "returns list of users" do
        before { user }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to be_an(Array)
        end
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        run_test!
      end
    end

    post "Register a new user" do
      tags     "Users"
      security []
      consumes "application/json"
      produces "application/json"
      description "Public endpoint. Creates a new account; no token is required " \
                  "because the user does not exist yet. After registering, obtain " \
                  "an access token via POST /oauth/token."
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            required: %w[email username first_name last_name password],
            properties: {
              email:               { type: :string, example: "ada@example.com" },
              username:            { type: :string, example: "ada_l" },
              first_name:          { type: :string, example: "Ada" },
              last_name:           { type: :string, example: "Lovelace" },
              password:            { type: :string, example: "Password1!" },
              preferred_language:  { type: :string, example: "en" },
              profile_picture_url: { type: :string, example: "https://example.com/me.png" }
            }
          }
        }
      }

      response "201", "user created" do
        let(:body) do
          { user: { email: "ada@example.com", username: "ada_l",
                    first_name: "Ada", last_name: "Lovelace",
                    password: "Password1!" } }
        end
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["username"]).to eq("ada_l")
          expect(data["email"]).to eq("ada@example.com")
        end
      end

      response "422", "invalid registration" do
        let(:body) { { user: { email: "bad", username: "x" } } }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("errors")
        end
      end
    end
  end

  path "/api/v1/users/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "Get a user" do
      tags     "Users"
      security [ { oauth2: [] } ]
      produces "application/json"

      response "200", "returns user profile" do
        let(:id) { user.id }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["username"]).to eq(user.username)
          expect(data.keys).not_to include("email")
        end
      end

      response "404", "user not found" do
        let(:id) { 0 }
        run_test!
      end
    end

    patch "Update a user" do
      tags        "Users"
      security    [ { oauth2: [] } ]
      consumes    "application/json"
      produces    "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            properties: {
              username:            { type: :string },
              email:               { type: :string },
              profile_picture_url: { type: :string }
            }
          }
        }
      }

      response "200", "user updated" do
        let(:id)   { user.id }
        let(:body) { { user: { username: "newname123" } } }
        run_test!
      end

      response "403", "forbidden cannot update another user" do
        let(:other) { create(:user) }
        let(:id)    { other.id }
        let(:body)  { { user: { username: "hacked" } } }
        run_test!
      end

      response "422", "invalid update" do
        let(:id)   { user.id }
        let(:body) { { user: { username: "a" } } } # too short / fails validation
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("errors")
        end
      end
    end
  end
end
