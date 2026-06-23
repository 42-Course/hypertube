require "rails_helper"
require "jwt"

# The streaming service authenticates these callbacks with a service-scope token
# signed using the shared secret; give the suite a deterministic one.
ENV["STREAM_TICKET_SECRET"] ||= "test-stream-ticket-secret"

RSpec.describe "Streaming callbacks API", type: :request do
  let(:path) { "/api/v1/streaming/callbacks/download_complete" }

  def service_auth
    { "Authorization" => "Bearer #{StreamTicket.service_token}" }
  end

  describe "POST /download_complete" do
    it "marks the movie downloaded when matched by media_id" do
      movie = create(:movie, media_id: "media-abc")

      post path, params: { media_id: "media-abc", file_path: "vod/media-abc/master.m3u8" },
                 headers: service_auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(movie.reload.file_path).to eq("vod/media-abc/master.m3u8")
      expect(movie.downloaded?).to be(true)
    end

    it "falls back to matching by info_hash against magnet_hash" do
      movie = create(:movie, magnet_hash: "ABCDEF0123", media_id: nil)

      post path, params: { info_hash: "abcdef0123" }, headers: service_auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(movie.reload.file_path).to be_present
    end

    it "returns 404 when no movie matches" do
      post path, params: { media_id: "missing" }, headers: service_auth, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "rejects a viewer-scope ticket (service scope required)" do
      movie = create(:movie)
      viewer = StreamTicket.issue(user: create(:user), movie: movie, media_id: "x")

      post path, params: { media_id: "x" },
                 headers: { "Authorization" => "Bearer #{viewer}" }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a missing/invalid token" do
      post path, params: { media_id: "x" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
