require "rails_helper"

RSpec.describe "Movie duration API", type: :request do
  let(:user)  { create(:user) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:auth)  { { "Authorization" => "Bearer #{token.token}" } }

  describe "PATCH /api/v1/movies/:id/duration" do
    it "stores the runtime (seconds -> minutes) when duration is blank" do
      movie = create(:movie, duration: nil)

      patch "/api/v1/movies/#{movie.id}/duration", params: { seconds: 5400 }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(movie.reload.duration).to eq(90)
      expect(JSON.parse(response.body)["duration"]).to eq(90)
    end

    it "does not overwrite a duration that already exists" do
      movie = create(:movie, duration: 120)

      patch "/api/v1/movies/#{movie.id}/duration", params: { seconds: 60 }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(movie.reload.duration).to eq(120)
    end

    it "ignores a non-positive value" do
      movie = create(:movie, duration: nil)

      patch "/api/v1/movies/#{movie.id}/duration", params: { seconds: 0 }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(movie.reload.duration).to be_nil
    end

    it "requires authentication" do
      movie = create(:movie)
      patch "/api/v1/movies/#{movie.id}/duration", params: { seconds: 60 }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
