module MovieSources
  # TMDb, a second movie-only source used for discovery and rich metadata
  # (popularity ranking, posters, overviews, genres). Requires an API key
  # (TMDB_API_KEY); when it is absent the source reports itself unavailable and
  # the aggregator simply skips it.
  # Docs: https://developer.themoviedb.org/reference/intro/getting-started
  class Tmdb < Base
    BASE_URL  = "https://api.themoviedb.org/3/".freeze
    IMAGE_URL = "https://image.tmdb.org/t/p/w500".freeze

    # TMDb returns numeric genre ids on list endpoints; map them to names once.
    GENRES = {
      28 => "Action", 12 => "Adventure", 16 => "Animation", 35 => "Comedy",
      80 => "Crime", 99 => "Documentary", 18 => "Drama", 10751 => "Family",
      14 => "Fantasy", 36 => "History", 27 => "Horror", 10402 => "Music",
      9648 => "Mystery", 10749 => "Romance", 878 => "Science Fiction",
      10770 => "TV Movie", 53 => "Thriller", 10752 => "War", 37 => "Western"
    }.freeze

    def available?
      api_key.present?
    end

    def search(query:, page: 1)
      return [] unless available?

      fetch("search/movie", query: query, page: page)
    end

    def popular(page: 1)
      return [] unless available?

      fetch("movie/popular", page: page)
    end

    CAST_LIMIT     = 15  # top-billed actors shown on the detail page
    PRODUCER_LIMIT = 4

    # Detail-level cast/crew lookup (not part of search/popular). Returns a
    # normalized credits hash, or nil when TMDb has no usable data so the
    # aggregator can fall back to another provider.
    def credits(movie)
      return nil unless available? && movie.tmdb_id.present?

      body = get_json("movie/#{movie.tmdb_id}/credits", api_key: api_key)
      cast = Array(body["cast"])
      crew = Array(body["crew"])
      return nil if cast.empty? && crew.empty?

      {
        "cast"      => cast.first(CAST_LIMIT).map { |member| cast_member(member) },
        "director"  => crew.find { |m| m["job"] == "Director" }&.fetch("name", nil),
        "producers" => crew.select { |m| m["job"] == "Producer" }
                           .map { |m| m["name"] }.first(PRODUCER_LIMIT),
        "source"    => "tmdb"
      }.compact_blank
    end

    private

    def cast_member(member)
      {
        "name"        => member["name"],
        "character"   => member["character"].presence,
        "profile_url" => poster_url(member["profile_path"])
      }.compact
    end

    def fetch(path, params)
      body  = get_json(path, params.merge(api_key: api_key))
      films = body["results"] || []
      films.map { |film| build_result(film) }
    end

    def build_result(film)
      Result.new(
        tmdb_id:    film["id"],
        title:      film["title"].presence || film["original_title"],
        year:       film["release_date"].to_s[0, 4].presence&.to_i,
        rating:     film["vote_average"],
        cover_url:  poster_url(film["poster_path"]),
        summary:    film["overview"].presence,
        genres:     genre_names(film["genre_ids"]),
        popularity: film["popularity"]
      )
    end

    def poster_url(path)
      "#{IMAGE_URL}#{path}" if path.present?
    end

    def genre_names(ids)
      Array(ids).filter_map { |id| GENRES[id] }.join(", ").presence
    end

    def api_key
      ENV["TMDB_API_KEY"].presence
    end
  end
end
