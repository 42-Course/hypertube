module MovieSources
  # Docs: https://prowlarr.com/docs/api/
  class Prowlarr < Base
    SEARCH_PATH    = "/api/v1/search".freeze
    MOVIE_CATEGORY = 2000 # Newznab/Torznab "Movies" parent category.
    LIMIT          = 100  # Releases per query, grouped per film below.

    def available?
      base_url.present? && api_key.present?
    end

    def search(query:, page: 1)
      return [] unless available?

      releases = get_json(SEARCH_PATH,
                          query:      query,
                          type:       "search",
                          categories: MOVIE_CATEGORY,
                          limit:      LIMIT,
                          offset:     (page - 1) * LIMIT)
      build_results(releases)
    end

    # Prowlarr has no popularity feed of its own; the front page is served by
    # TMDb, and magnets are attached on demand when a film is opened.
    def popular(page: 1)
      []
    end

    private

    # Prowlarr's search returns a bare JSON array of releases (get_json hands
    # back {} on failure, hence the type guard). A single film yields many
    # releases (qualities, release groups), so we group them and emit one Result
    # per film, keeping the most-seeded torrent.
    def build_results(releases)
      return [] unless releases.is_a?(Array)

      releases
        .select { |r| r["protocol"] == "torrent" && info_hash(r).present? }
        .group_by { |r| group_key(r) }
        .values
        .map { |group| build_result(group) }
    end

    def build_result(group)
      best = group.max_by { |r| r["seeders"].to_i }
      Result.new(
        imdb_id:     imdb_id(best),
        tmdb_id:     tmdb_id(best),
        title:       clean_title(best),
        year:        release_year(best),
        magnet_hash: info_hash(best),
        # Total seeders across every release of the film: a reasonable
        # availability/popularity signal when TMDb is unavailable.
        popularity:  group.sum { |r| r["seeders"].to_i }
      )
    end

    def group_key(release)
      return "tmdb:#{tmdb_id(release)}" if tmdb_id(release)
      return "imdb:#{imdb_id(release)}" if imdb_id(release)

      "title:#{clean_title(release).to_s.downcase}"
    end

    # Prowlarr returns the IMDb id as a bare integer (e.g. 1375666); restore the
    # canonical "tt0000000" form used everywhere else in the app.
    def imdb_id(release)
      id = release["imdbId"].to_i
      id.positive? ? format("tt%07d", id) : nil
    end

    def tmdb_id(release)
      id = release["tmdbId"].to_i
      id.positive? ? id : nil
    end

    # Prefer the explicit info-hash; fall back to parsing it out of the magnet
    # URI. Normalised to upper-case so the same torrent dedupes consistently.
    def info_hash(release)
      hash = release["infoHash"].presence
      hash ||= release["magnetUrl"].to_s[/btih:([0-9a-fA-F]+)/, 1]
      hash&.upcase
    end

    # Best-effort clean title from a raw release name
    # ("Inception.2010.1080p.BluRay" -> "Inception"). Used only as a fallback
    # display title when the film is not also matched against TMDb.
    def clean_title(release)
      raw = release["title"].to_s
      cut = raw =~ /\b(?:19|20)\d{2}\b/
      raw = raw[0...cut] if cut
      cleaned = raw.tr("._", " ").squish
      # A parenthesised year ("The Movie (2026)") leaves a dangling separator
      # once the year is cut; strip trailing brackets/dashes/colons/space.
      cleaned = cleaned.sub(/[\s(\[{\-–—:|]+\z/, "")
      cleaned.presence || release["title"]
    end

    def release_year(release)
      release["title"].to_s[/\b(?:19|20)\d{2}\b/]&.to_i
    end

    def base_url
      ENV["PROWLARR_URL"].presence&.chomp("/")
    end

    def api_key
      ENV["PROWLARR_API_KEY"].presence
    end

    # Override Base#connection: the host is dynamic (env-configured, not a
    # constant) and Prowlarr authenticates via the X-Api-Key header.
    def connection
      @connection ||= Faraday.new(url: base_url) do |f|
        f.options.timeout      = 8
        f.options.open_timeout = 4
        f.headers["Accept"]    = "application/json"
        f.headers["X-Api-Key"] = api_key
      end
    end
  end
end
