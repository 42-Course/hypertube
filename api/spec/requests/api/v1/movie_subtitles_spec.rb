require "rails_helper"

RSpec.describe "Movie subtitles API", type: :request do
  let(:user)  { create(:user) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:auth)  { { "Authorization" => "Bearer #{token.token}" } }

  describe "GET /api/v1/movies/:id/subtitles" do
    it "returns the cached subtitle languages" do
      movie = create(:movie, subtitle_languages: %w[en fr])

      get "/api/v1/movies/#{movie.id}/subtitles", headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["languages"]).to eq(%w[en fr])
    end

    it "returns no languages when OpenSubtitles is unavailable" do
      movie = create(:movie, subtitle_languages: [])

      get "/api/v1/movies/#{movie.id}/subtitles", headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["languages"]).to eq([])
    end

    it "requires authentication" do
      movie = create(:movie)
      get "/api/v1/movies/#{movie.id}/subtitles"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/movies/:id/subtitles/:language" do
    it "serves WebVTT converted from the source subtitle" do
      movie = create(:movie)
      allow_any_instance_of(MovieSources::OpenSubtitles)
        .to receive(:vtt).with(an_instance_of(Movie), "en")
        .and_return("WEBVTT\n\n1\n00:00:01.000 --> 00:00:02.000\nHi\n")

      get "/api/v1/movies/#{movie.id}/subtitles/en", headers: auth

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vtt")
      expect(response.body).to start_with("WEBVTT")
    end

    it "returns 404 when the subtitle is unavailable" do
      movie = create(:movie)
      allow_any_instance_of(MovieSources::OpenSubtitles).to receive(:vtt).and_return(nil)

      get "/api/v1/movies/#{movie.id}/subtitles/en", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end
end
