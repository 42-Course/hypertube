require "swagger_helper"

# The stream-ticket endpoint signs JWTs with a shared secret; give the suite a
# deterministic one.
ENV["STREAM_TICKET_SECRET"] ||= "test-stream-ticket-secret"

RSpec.describe "Movies API", type: :request do
  let(:user)  { create(:user) }
  let(:token) { create(:doorkeeper_access_token, resource_owner_id: user.id) }
  let(:Authorization) { "Bearer #{token.token}" }

  path "/api/v1/movies" do
    get "List saved movies (local catalog)" do
      tags        "Movies"
      produces    "application/json"
      description "Public. Browses movies already saved in our DB (everything " \
                  "anyone has searched/opened). Pure DB query paginated and " \
                  "filterable. Use /movies/search to discover new films."
      parameter name: :query,      in: :query, type: :string,  required: false,
                                   description: "matches the title"
      parameter name: :genre,      in: :query, type: :string,  required: false
      parameter name: :min_year,   in: :query, type: :integer, required: false
      parameter name: :max_year,   in: :query, type: :integer, required: false
      parameter name: :min_rating, in: :query, type: :number,  required: false
      parameter name: :sort,       in: :query, type: :string,  required: false,
                                   description: "name | year | rating | popularity"
      parameter name: :order,      in: :query, type: :string,  required: false,
                                   description: "asc | desc"
      parameter name: :page,       in: :query, type: :integer, required: false
      parameter name: :per_page,   in: :query, type: :integer, required: false,
                                   description: "1-100 (default 20)"

      response "200", "returns paginated saved movies" do
        before do
          create(:movie, title: "Inception", year: 2010, rating: 8.8, popularity: 100, genres: [ 'Suspense' ])
          create(:movie, title: "Arrival",   year: 2016, rating: 7.9, popularity: 50)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(2)
          expect(data["page"]).to eq(1)
          expect(data["per_page"]).to eq(20)
          expect(data["total_pages"]).to eq(1)
          expect(data["movies"].map { |m| m["title"] }).to contain_exactly("Inception", "Arrival")
        end
      end

      response "200", "filters the catalog by genre" do
        before do
          create(:movie, title: "Inception", year: 2010, rating: 8.8, popularity: 100, genres: [ 'Suspense' ])
          create(:movie, title: "Arrival",   year: 2016, rating: 7.9, popularity: 50)
        end

        let(:genre)       { "Suspense" }
        let(:min_year)    { 1900 }
        let(:max_year)    { 2020 }
        let(:min_rating)  { 1 }
        let(:sort)        { "name" }
        let(:order)       { "asc" }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(1)
          expect(data["movies"].first["title"]).to eq("Inception")
        end
      end

      response "200", "filters and paginates the catalog" do
        let(:query)    { "incep" }
        let(:per_page) { 1 }
        before do
          create(:movie, title: "Inception", year: 2010, rating: 8.8)
          create(:movie, title: "Arrival",   year: 2016, rating: 7.9)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["total"]).to eq(1)
          expect(data["movies"].size).to eq(1)
          expect(data["movies"].first["title"]).to eq("Inception")
        end
      end
    end
  end

  path "/api/v1/movies/search" do
    get "Search movies (external sources)" do
      tags        "Movies"
      produces    "application/json"
      description "Public. Queries the external sources (TMDb + Prowlarr), " \
                  "persists each film locally, then sorts/filters/paginates. " \
                  "With no query, returns the most popular films."
      parameter name: :query,      in: :query, type: :string,  required: false
      parameter name: :page,       in: :query, type: :integer, required: false
      parameter name: :sort,       in: :query, type: :string,  required: false,
                                   description: "name | year | rating | genre | popularity"
      parameter name: :order,      in: :query, type: :string,  required: false,
                                   description: "asc | desc"
      parameter name: :genre,      in: :query, type: :string,  required: false
      parameter name: :min_year,   in: :query, type: :integer, required: false
      parameter name: :max_year,   in: :query, type: :integer, required: false
      parameter name: :min_rating, in: :query, type: :number,  required: false

      # The aggregator talks to external sources; stub it so this doc/contract
      # spec stays offline and deterministic. Real HTTP is covered in
      # spec/services/movie_sources.
      before do
        allow_any_instance_of(MovieSources::Aggregator)
          .to receive(:list).and_return([ create(:movie, title: "Inception") ])
      end

      response "200", "returns aggregated, persisted movies" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("movies")
          expect(data["page"]).to eq(1)
          expect(data["movies"].first["title"]).to eq("Inception")
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

      before do
        allow_any_instance_of(MovieSources::Aggregator)
          .to receive(:enrich) { |_agg, movie| movie }
      end

      response "200", "returns movie details" do
        let(:movie) do
          create(:movie, credits: {
            "cast"     => [ { "name" => "Leonardo DiCaprio", "character" => "Cobb" } ],
            "director" => "Christopher Nolan", "producers" => [ "Emma Thomas" ]
          })
        end
        let(:id) { movie.id }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["id"]).to eq(movie.id)
          expect(data).to have_key("comments_count")
          expect(data).to have_key("subtitles")
          expect(data["director"]).to eq("Christopher Nolan")
          expect(data["producers"]).to eq([ "Emma Thomas" ])
          expect(data["cast"].first["name"]).to eq("Leonardo DiCaprio")
        end
      end

      response "404", "movie not found" do
        let(:id) { 0 }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to eq("Movie not found")
        end
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        let(:id) { 1 }
        run_test!
      end
    end
  end

  path "/api/v1/movies/{id}/stream_ticket" do
    post "Mint a stream ticket for a movie" do
      tags        "Movies"
      produces    "application/json"
      security    [ { oauth2: [] } ]
      description "Returns a short-lived, movie-scoped signed ticket (JWT) the " \
                  "browser hands directly to the streaming service, which " \
                  "verifies it locally with the shared secret. The user's API " \
                  "token never leaves the API boundary."
      parameter name: :id, in: :path, type: :integer, required: true

      response "201", "ticket issued" do
        let(:movie) { create(:movie, magnet_hash: "ABCDEF0123456789ABCDEF0123456789ABCDEF01") }
        let(:id)    { movie.id }

        before do
          # Stub the movie->media handoff so the suite stays hermetic (no live
          # streaming service). Asserts the API forwards the resolved magnet.
          allow_any_instance_of(StreamingService)
            .to receive(:ensure_media)
            .with(magnet: movie.magnet_uri)
            .and_return("0123456789abcdef0123456789abcdef")
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["token_type"]).to eq("Bearer")
          expect(data["expires_in"]).to eq(StreamTicket::TTL.to_i)
          expect(data["media_id"]).to eq("0123456789abcdef0123456789abcdef")

          claims = StreamTicket.verify(data["ticket"])
          expect(claims["sub"]).to eq(user.id.to_s)
          expect(claims["movie_id"]).to eq(movie.id)
          expect(claims["media_id"]).to eq("0123456789abcdef0123456789abcdef")
          expect(claims["scope"]).to eq(StreamTicket::SCOPE)
        end
      end

      response "422", "movie has no torrent yet" do
        let(:movie) { create(:movie, magnet_hash: nil) }
        let(:id)    { movie.id }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to eq("no_torrent")
        end
      end

      response "502", "streaming service unavailable" do
        let(:movie) { create(:movie, magnet_hash: "ABCDEF0123456789ABCDEF0123456789ABCDEF01") }
        let(:id)    { movie.id }

        before do
          allow_any_instance_of(StreamingService)
            .to receive(:ensure_media)
            .and_raise(StreamingService::Error, "streaming service unreachable")
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to eq("streaming_unavailable")
        end
      end

      response "404", "movie not found" do
        let(:id) { 0 }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["error"]).to eq("Movie not found")
        end
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        let(:id) { 1 }
        run_test!
      end
    end
  end

  path "/api/v1/movies/{id}/watched" do
    parameter name: :id, in: :path, type: :integer, required: true

    post "Mark a movie as watched" do
      tags     "Movies"
      produces "application/json"
      security [ { oauth2: [] } ]
      description "Records that the current user has watched this movie. " \
                  "Idempotent. Returns the refreshed detail payload."

      response "200", "movie marked watched" do
        let(:movie) { create(:movie) }
        let(:id)    { movie.id }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["watched"]).to be(true)
          expect(movie.watched_by?(user)).to be(true)
        end
      end

      response "404", "movie not found" do
        let(:id) { 0 }
        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to eq("Movie not found")
        end
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        let(:id) { 1 }
        run_test!
      end
    end

    delete "Mark a movie as unwatched" do
      tags     "Movies"
      produces "application/json"
      security [ { oauth2: [] } ]
      description "Clears the current user's watched mark for this movie. " \
                  "Idempotent."

      response "200", "movie marked unwatched" do
        let(:movie) { create(:movie) }
        let(:id)    { movie.id }

        before { movie.mark_watched_by(user) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["watched"]).to be(false)
          expect(movie.watched_by?(user)).to be(false)
        end
      end

      response "404", "movie not found" do
        let(:id) { 0 }
        run_test! do |response|
          expect(JSON.parse(response.body)["error"]).to eq("Movie not found")
        end
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        let(:id) { 1 }
        run_test!
      end
    end
  end
end
