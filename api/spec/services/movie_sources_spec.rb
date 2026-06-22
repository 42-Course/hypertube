require "rails_helper"

RSpec.describe "MovieSources", type: :service do
  let(:prowlarr_url)     { "https://prowlarr.test" }
  let(:prowlarr_search)  { "#{prowlarr_url}/api/v1/search" }
  let(:tmdb_popular_url) { "https://api.themoviedb.org/3/movie/popular" }
  let(:tmdb_search_url)  { "https://api.themoviedb.org/3/search/movie" }

  # Regex matchers ignore query strings, handy for stubs where we don't want to
  # pin every query param (limit, page, sort_by, api_key, ...).
  let(:prowlarr_any)     { %r{prowlarr\.test/api/v1/search} }
  let(:tmdb_popular_any) { %r{api\.themoviedb\.org/3/movie/popular} }

  def tmdb_body(results)
    { page: 1, results: results }.to_json
  end

  # A single film comes back from Prowlarr as several releases (qualities,
  # release groups); the source must collapse them into one Result.
  let(:prowlarr_top) do
    {
      "protocol" => "torrent", "title" => "Inception.2010.1080p.BluRay.x264",
      "infoHash" => "TOPSEED", "seeders" => 200,
      "imdbId" => 1375666, "tmdbId" => 27205
    }
  end

  let(:prowlarr_mid) do
    {
      "protocol" => "torrent", "title" => "Lord.Of.The.Rings.2001.mp4",
      "infoHash" => "TOPSEED", "seeders" => 100,
      "tmdbId" => 27201
    }
  end

  let(:prowlarr_low) do
    {
      "protocol" => "torrent", "title" => "Inception.2010.720p.WEB-DL",
      "infoHash" => "LOWSEED", "seeders" => 50,
      "imdbId" => 1375666, "tmdbId" => 27205
    }
  end

  let(:tmdb_inception) do
    {
      "id" => 27205, "title" => "Inception", "release_date" => "2010-07-16",
      "vote_average" => 8.4, "poster_path" => "/poster.jpg",
      "overview" => "Dom Cobb is a skilled thief.", "genre_ids" => [ 28, 878 ],
      "popularity" => 142.5
    }
  end

  describe MovieSources::Prowlarr do
    subject(:source) { described_class.new }

    before do
      allow(source).to receive_messages(base_url: prowlarr_url, api_key: "test-key")
    end

    it "is unavailable without a URL or API key" do
      allow(source).to receive(:base_url).and_return(nil)
      expect(source).not_to be_available
      expect(source.search(query: "x")).to eq([])
    end

    it "groups releases per film and keeps the most-seeded torrent" do
      stub = stub_request(:get, prowlarr_search)
             .with(query: hash_including("query" => "inception"))
             .to_return(status: 200, body: [ prowlarr_low, prowlarr_top ].to_json,
                        headers: { "Content-Type" => "application/json" })

      results = source.search(query: "inception")

      expect(stub).to have_been_requested
      expect(results.size).to eq(1)
      result = results.first
      expect(result.imdb_id).to eq("tt1375666")
      expect(result.tmdb_id).to eq(27205)
      expect(result.title).to eq("Inception")
      expect(result.year).to eq(2010)
      expect(result.magnet_hash).to eq("TOPSEED")   # 200 seeders beats 50
      expect(result.popularity).to eq(250)          # total seeders across releases
    end

    it "does not leave a dangling bracket when the year is parenthesised" do
      release = {
        "protocol" => "torrent", "infoHash" => "ABC123",
        "title" => "The Super Mario Galaxy Movie (2026) 1080p WEBRip x265"
      }
      stub_request(:get, prowlarr_any)
        .to_return(status: 200, body: [ release ].to_json,
                   headers: { "Content-Type" => "application/json" })

      result = source.search(query: "mario").first
      expect(result.title).to eq("The Super Mario Galaxy Movie")
      expect(result.year).to eq(2026)
    end

    it "skips releases without a usable info-hash" do
      stub_request(:get, prowlarr_any)
        .to_return(status: 200,
                   body: [ { "protocol" => "torrent", "title" => "No Hash 2020" } ].to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(source.search(query: "anything")).to eq([])
    end

    it "returns [] when the source is unreachable" do
      stub_request(:get, prowlarr_any).to_timeout
      expect(source.search(query: "inception")).to eq([])
    end
  end

  describe MovieSources::Tmdb do
    subject(:source) { described_class.new }

    before { allow(source).to receive(:api_key).and_return("test-key") }

    it "is unavailable without an API key" do
      allow(source).to receive(:api_key).and_return(nil)
      expect(source).not_to be_available
      expect(source.popular).to eq([])
    end

    it "normalizes popular results and builds full image/genre fields" do
      stub_request(:get, tmdb_popular_url)
        .with(query: hash_including("api_key" => "test-key"))
        .to_return(status: 200, body: tmdb_body([ tmdb_inception ]),
                   headers: { "Content-Type" => "application/json" })

      result = source.popular.first
      expect(result.tmdb_id).to eq(27205)
      expect(result.year).to eq(2010)
      expect(result.cover_url).to eq("https://image.tmdb.org/t/p/w500/poster.jpg")
      expect(result.genres).to eq("Action, Science Fiction")
      expect(result.popularity).to eq(142.5)
    end
  end

  describe MovieSources::Aggregator do
    let(:tmdb)     { MovieSources::Tmdb.new }
    let(:prowlarr) { MovieSources::Prowlarr.new }

    before do
      allow(tmdb).to receive(:api_key).and_return("test-key")
      allow(prowlarr).to receive_messages(base_url: prowlarr_url, api_key: "test-key")

      stub_request(:get, prowlarr_any)
        .to_return(status: 200, body: [ prowlarr_low, prowlarr_mid, prowlarr_top ].to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, tmdb_popular_any)
        .to_return(status: 200, body: tmdb_body([ tmdb_inception ]),
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, %r{api\.themoviedb\.org/3/search/movie})
        .to_return(status: 200, body: tmdb_body([ tmdb_inception ]),
                   headers: { "Content-Type" => "application/json" })
    end

    subject(:aggregator) { described_class.new(sources: [ tmdb, prowlarr ]) }

    it "merges the same film from both sources into one persisted movie" do
      expect { aggregator.list(query: "inception") }.to change(Movie, :count).by(2)

      movie = Movie.first
      expect(movie.tmdb_id).to eq(27205)              # shared id
      expect(movie.imdb_id).to eq("tt1375666")        # from Prowlarr
      expect(movie.magnet_hash).to eq("TOPSEED")      # from Prowlarr
      expect(movie.title).to eq("Inception")          # TMDb wins (listed first)
      expect(movie.cover_url).to be_present            # from TMDb
    end

    it "is idempotent: re-listing updates the existing record, not a new one" do
      aggregator.list(query: "inception")
      expect { aggregator.list(query: "inception") }.not_to change(Movie, :count)
    end

    it "filters by minimum rating" do
      expect(aggregator.list(query: "inception", min_rating: 9.0)).to be_empty
      expect(aggregator.list(query: "inception", min_rating: 8.0)).not_to be_empty
    end

    it "sorts search results by name by default" do
      zodiac  = tmdb_inception.merge("id" => 1, "title" => "Zodiac", "release_date" => "2007-03-02")
      arrival = tmdb_inception.merge("id" => 2, "title" => "Arrival", "release_date" => "2016-11-11")
      stub_request(:get, %r{api\.themoviedb\.org/3/search/movie})
        .to_return(status: 200, body: tmdb_body([ zodiac, arrival ]),
                   headers: { "Content-Type" => "application/json" })
      allow(prowlarr).to receive(:available?).and_return(false)

      titles = aggregator.list(query: "a").map(&:title)
      expect(titles).to eq([ "Arrival", "Zodiac" ])
    end

    describe "#enrich (magnet + metadata)" do
      # Stubbed resolver (TMDb search) and no credit providers: keeps the
      # magnet/metadata cases hermetic. Credits get their own block below.
      subject(:aggregator) do
        described_class.new(sources: [ tmdb, prowlarr ], resolver: tmdb, credit_providers: [])
      end

      it "resolves a missing magnet even when display metadata is already present" do
        # The bug this fixes: a TMDb-sourced film has summary+cover but no
        # magnet, so the old early-return skipped Prowlarr and it never got one.
        movie = create(:movie, title: "Inception", year: 2010, tmdb_id: 27205,
                               summary: "Dom Cobb.", cover_url: "https://img/x.jpg",
                               magnet_hash: nil)

        expect { aggregator.enrich(movie) }
          .to change { movie.reload.magnet_hash }.from(nil).to("TOPSEED")
      end

      it "does not look for a magnet when one is already present" do
        movie = create(:movie, title: "Inception", summary: "x",
                               cover_url: "y", magnet_hash: "EXISTING")

        aggregator.enrich(movie)

        expect(a_request(:get, prowlarr_any)).not_to have_been_made
        expect(movie.reload.magnet_hash).to eq("EXISTING")
      end
    end

    describe "#enrich (cast/crew)" do
      let(:omdb) { MovieSources::Omdb.new }

      subject(:aggregator) do
        described_class.new(sources: [ tmdb, prowlarr ], resolver: tmdb,
                            credit_providers: [ tmdb, omdb ])
      end

      before { allow(omdb).to receive(:api_key).and_return("omdb-key") }

      it "stores TMDb cast (with photos/characters) and crew on first view" do
        stub_request(:get, %r{api\.themoviedb\.org/3/movie/27205/credits})
          .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                     body: {
                       cast: [
                         { "name" => "Leonardo DiCaprio", "character" => "Cobb", "profile_path" => "/leo.jpg" },
                         { "name" => "Elliot Page", "character" => "Ariadne" }
                       ],
                       crew: [
                         { "name" => "Christopher Nolan", "job" => "Director" },
                         { "name" => "Emma Thomas", "job" => "Producer" }
                       ]
                     }.to_json)

        movie = create(:movie, title: "Inception", tmdb_id: 27205,
                               summary: "x", cover_url: "y", magnet_hash: "M")

        aggregator.enrich(movie)
        movie.reload

        expect(movie.director).to eq("Christopher Nolan")
        expect(movie.producers).to eq([ "Emma Thomas" ])
        expect(movie.cast.first).to include(
          "name" => "Leonardo DiCaprio", "character" => "Cobb",
          "profile_url" => "https://image.tmdb.org/t/p/w500/leo.jpg"
        )
      end

      it "falls back to OMDb (IMDb) when TMDb has no credits" do
        movie = create(:movie, title: "Obscure", tmdb_id: nil, imdb_id: "tt9999999",
                               summary: "x", cover_url: "y", magnet_hash: "M")
        stub_request(:get, %r{omdbapi\.com})
          .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                     body: { "Response" => "True", "Actors" => "Jane Doe, John Roe",
                             "Director" => "Some Director", "Writer" => "A Writer" }.to_json)

        aggregator.enrich(movie)
        movie.reload

        expect(movie.cast.map { |c| c["name"] }).to eq([ "Jane Doe", "John Roe" ])
        expect(movie.director).to eq("Some Director")
      end
    end

    describe "#list identity resolution" do
      # The screenshot bug: a search returns many thumbnail-less Prowlarr release
      # cards for the same film. Sparse releases (no ids/poster) are resolved by
      # title against TMDb, so they gain a poster AND collapse into one movie.
      subject(:aggregator) { described_class.new(sources: [ prowlarr ], resolver: tmdb) }

      before do
        # Two releases of the same film with DIFFERENT messy titles (so Prowlarr
        # keeps them as separate groups) and no ids.
        release_a = { "protocol" => "torrent", "title" => "TPB AFK 2013 1080p",
                      "infoHash" => "AAA", "seeders" => 10 }
        release_b = { "protocol" => "torrent", "title" => "The Pirate Bay Away From Keyboard 2013",
                      "infoHash" => "BBB", "seeders" => 5 }
        stub_request(:get, prowlarr_any)
          .to_return(status: 200, body: [ release_a, release_b ].to_json,
                     headers: { "Content-Type" => "application/json" })

        # TMDb maps both messy titles to the same canonical film.
        tpb = { "id" => 12345, "title" => "TPB AFK: The Pirate Bay Away From Keyboard",
                "release_date" => "2013-01-01", "poster_path" => "/tpb.jpg",
                "overview" => "Documentary.", "vote_average" => 7.1 }
        stub_request(:get, %r{api\.themoviedb\.org/3/search/movie})
          .to_return(status: 200, body: tmdb_body([ tpb ]),
                     headers: { "Content-Type" => "application/json" })
      end

      it "collapses duplicate releases into one movie with a poster" do
        expect { aggregator.list(query: "tpb afk") }.to change(Movie, :count).by(1)

        movie = Movie.first
        expect(movie.tmdb_id).to eq(12345)
        expect(movie.title).to eq("TPB AFK: The Pirate Bay Away From Keyboard")
        expect(movie.cover_url).to be_present      # gained from TMDb
        expect(movie.magnet_hash).to be_present    # kept from a release
      end
    end
  end

  describe "Redis caching" do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(memory_cache) }

    it "memoizes a source response so the API is hit only once" do
      source = MovieSources::Prowlarr.new
      allow(source).to receive_messages(base_url: prowlarr_url, api_key: "test-key")
      stub = stub_request(:get, prowlarr_any)
             .to_return(status: 200, body: [ prowlarr_top ].to_json,
                        headers: { "Content-Type" => "application/json" })

      2.times { source.search(query: "inception") }

      expect(stub).to have_been_requested.once
    end
  end
end
