module MovieSources
  # OMDb (IMDb-derived data), used only as a credits fallback when TMDb has no
  # cast for a film but we hold its IMDb id. It is not a discovery source, so it
  # implements neither #search nor #popular; the aggregator calls #credits only.
  # Requires OMDB_API_KEY; absent that it reports itself unavailable.
  # Docs: https://www.omdbapi.com/
  class Omdb < Base
    BASE_URL = "https://www.omdbapi.com/".freeze

    def available?
      api_key.present?
    end

    # Detail-level cast/crew lookup by IMDb id. OMDb returns a short, comma-
    # separated actor list (no characters or photos) plus director/writer.
    # Returns nil when unusable so resolution stops here.
    def credits(movie)
      return nil unless available? && movie.imdb_id.present?

      body = get_json("", i: movie.imdb_id, apikey: api_key)
      return nil unless body["Response"] == "True"

      cast = split_list(body["Actors"])
      return nil if cast.empty? && present(body["Director"]).nil?

      {
        "cast"      => cast.map { |name| { "name" => name } },
        "director"  => present(body["Director"]),
        "writer"    => present(body["Writer"]),
        "source"    => "omdb"
      }.compact_blank
    end

    private

    # OMDb fills unknown fields with the literal string "N/A".
    def split_list(value)
      value.to_s.split(",").map(&:strip).reject { |v| v.empty? || v == "N/A" }
    end

    def present(value)
      stripped = value.to_s.strip
      stripped.empty? || stripped == "N/A" ? nil : stripped
    end

    def api_key
      ENV["OMDB_API_KEY"].presence
    end
  end
end
