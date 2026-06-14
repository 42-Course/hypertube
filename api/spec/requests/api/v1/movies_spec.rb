require "swagger_helper"

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
        let(:movie) { create(:movie) }
        let(:id)    { movie.id }
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["id"]).to eq(movie.id)
          expect(data).to have_key("comments_count")
          expect(data).to have_key("subtitles")
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
end
