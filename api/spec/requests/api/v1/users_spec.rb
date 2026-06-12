require "swagger_helper"

RSpec.describe "Users API", type: :request do
  let(:user)  { create(:user) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:Authorization) { "Bearer #{token.token}" }

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

      response "403", "forbidden — cannot update another user" do
        let(:other) { create(:user) }
        let(:id)    { other.id }
        let(:body)  { { user: { username: "hacked" } } }
        run_test!
      end
    end
  end
end
