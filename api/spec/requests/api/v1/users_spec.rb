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
          expect(data["first_name"]).to eq(user.first_name)
          expect(data["last_name"]).to eq(user.last_name)
          expect(data.keys).to include("preferred_language", "profile_picture_url")
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
      consumes    "multipart/form-data"
      produces    "application/json"
      description "Update the authenticated user's own profile. Sent as " \
                  "multipart/form-data so a profile image (`avatar`) can be " \
                  "uploaded; the image is stored via Active Storage and its " \
                  "URL is returned in `profile_picture_url`."
      # Single multipart object so the avatar shows up as a binary upload in the
      # docs. `getter:` keeps the form field name "user" (-> params[:user]) while
      # the value comes from `let(:user_payload)`, avoiding a clash with the
      # top-level `let(:user)` (the authenticated account).
      parameter name: :user, in: :formData, getter: :user_payload, required: false,
                schema: {
                  type: :object,
                  properties: {
                    username:           { type: :string },
                    first_name:         { type: :string },
                    last_name:          { type: :string },
                    preferred_language: { type: :string },
                    avatar:             { type: :string, format: :binary,
                                          description: "Profile image file" }
                  }
                }

      response "200", "user updated" do
        let(:id)           { user.id }
        let(:user_payload) { { username: "newname123" } }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["username"]).to eq("newname123")
        end
      end

      response "200", "avatar uploaded" do
        let(:id) { user.id }
        let(:user_payload) do
          { avatar: Rack::Test::UploadedFile.new(
            Rails.root.join("spec/fixtures/files/avatar.png"), "image/png"
          ) }
        end
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(user.reload.avatar).to be_attached
          expect(data["profile_picture_url"]).to include("/rails/active_storage/")
        end
      end

      response "403", "forbidden cannot update another user" do
        let(:other)        { create(:user) }
        let(:id)           { other.id }
        let(:user_payload) { { username: "hacked" } }
        run_test!
      end

      response "422", "invalid update" do
        let(:id)           { user.id }
        let(:user_payload) { { username: "a" } } # too short / fails validation
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("errors")
        end
      end
    end
  end

  path "/api/v1/users/{id}/movies" do
    parameter name: :id, in: :path, type: :integer

    get "List a user's watched movies" do
      tags     "Users"
      security [ { oauth2: [] } ]
      produces "application/json"
      description "Paginated list of the movies this user has watched " \
                  "(same payload shape as GET /movies)."
      parameter name: :page,     in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false,
                                 description: "1-100 (default 20)"

      response "200", "returns the user's watched movies (paginated)" do
        let(:id) { user.id }
        before do
          inception = create(:movie, title: "Inception")
          arrival   = create(:movie, title: "Arrival")
          create(:watch_history, user: user, movie: inception)
          create(:watch_history, user: user, movie: arrival)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(2)
          expect(data["page"]).to eq(1)
          expect(data["per_page"]).to eq(20)
          expect(data["total_pages"]).to eq(1)
          expect(data["movies"].map { |m| m["title"] })
            .to contain_exactly("Inception", "Arrival")
        end
      end

      response "200", "paginates the watched movies" do
        let(:id)       { user.id }
        let(:per_page) { 1 }
        before do
          create(:watch_history, user: user, movie: create(:movie, title: "Inception"))
          create(:watch_history, user: user, movie: create(:movie, title: "Arrival"))
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(2)
          expect(data["total_pages"]).to eq(2)
          expect(data["movies"].size).to eq(1)
        end
      end

      response "404", "user not found" do
        let(:id) { 0 }
        run_test!
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        let(:id)            { user.id }
        run_test!
      end
    end
  end
end
