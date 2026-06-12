require "swagger_helper"

RSpec.describe "Movies API", type: :request do
  let(:user)  { create(:user) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:Authorization) { "Bearer #{token.token}" }

  path "/api/v1/movies" do
    get "List top movies (public)" do
      tags     "Movies"
      produces "application/json"

      response "200", "returns movie list" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("movies")
        end
      end
    end
  end

  path "/api/v1/movies/{id}" do
    parameter name: :id, in: :path, type: :integer

    get "Get movie details" do
      tags     "Movies"
      security [ { oauth2: [] } ]
      produces "application/json"

      response "200", "returns movie details" do
        let(:movie) { create(:movie) }
        let(:id)    { movie.id }
        run_test!
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        let(:id) { 1 }
        run_test!
      end
    end
  end
end
