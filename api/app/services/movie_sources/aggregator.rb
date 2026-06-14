module MovieSources
  # Orchestrates the external sources for the Movies API.
  #
  #   list  -> query every available source, merge duplicates, persist each
  #            film locally (so it gets a stable id and can hold comments),
  #            then filter/sort/paginate the result set.
  #   enrich -> top up a single stored movie's metadata on the detail view.
  #
  # TMDb is listed first so its clean title and rich metadata (poster, overview,
  # rating, popularity) win when the same film also comes back from Prowlarr;
  # Prowlarr then fills the one thing TMDb lacks, the torrent magnet hash.
  class Aggregator
    SORTABLE = %w[name year rating genre popularity].freeze

    def initialize(sources: nil)
      @sources = sources || [ Tmdb.new, Prowlarr.new ]
    end

    # @return [Array<Movie>] persisted, filtered, sorted, paginated.
    def list(query: nil, page: 1, per_page: 20, **filters)
      results = collect(query: query, page: page)
      movies  = merge(results).map { |result| Movie.upsert_from_source(result) }
      movies  = apply_filters(movies, **filters.slice(:genre, :min_year, :max_year, :min_rating))
      movies  = apply_sort(movies, query: query, sort: filters[:sort], order: filters[:order])
      movies.first(per_page)
    end

    # Best-effort metadata top-up for a single movie shown on its detail page.
    # Only reaches out when something is missing, and never raises.
    def enrich(movie)
      return movie if movie.summary.present? && movie.cover_url.present?
      return movie if movie.title.blank?

      results = collect(query: movie.title, page: 1)
      match   = merge(results).find { |r| same_film?(r, movie) }
      movie.upsert_attributes_from_source(match) if match
      movie
    end

    private

    def collect(query:, page:)
      @sources.select(&:available?).flat_map do |source|
        query.present? ? source.search(query: query, page: page) : source.popular(page: page)
      rescue StandardError => e
        Rails.logger.warn("[MovieSources] #{source.class}: #{e.class} #{e.message}")
        []
      end
    end

    # Fold results sharing a dedupe key into one, preserving source precedence.
    def merge(results)
      results.each_with_object({}) do |result, by_key|
        key = result.dedupe_key
        by_key[key] ? by_key[key].merge(result) : by_key[key] = result
      end.values
    end

    def apply_filters(movies, genre: nil, min_year: nil, max_year: nil, min_rating: nil)
      movies = movies.select { |m| m.genres.to_s.downcase.include?(genre.downcase) } if genre.present?
      movies = movies.select { |m| m.year.to_i >= min_year.to_i }   if min_year.present?
      movies = movies.select { |m| m.year.to_i <= max_year.to_i }   if max_year.present?
      movies = movies.select { |m| m.rating.to_f >= min_rating.to_f } if min_rating.present?
      movies
    end

    def apply_sort(movies, query:, sort:, order:)
      # Subject: search results default to name order; the front page to popularity.
      sort  = (SORTABLE.include?(sort) ? sort : (query.present? ? "name" : "popularity"))
      desc  = order.present? ? order.to_s.downcase == "desc" : sort == "popularity"

      sorted = movies.sort_by { |m| sort_key(m, sort) }
      desc ? sorted.reverse : sorted
    end

    def sort_key(movie, sort)
      case sort
      when "year"       then movie.year.to_i
      when "rating"     then movie.rating.to_f
      when "popularity" then movie.popularity.to_f
      when "genre"      then movie.genres.to_s.downcase
      else                   movie.title.to_s.downcase
      end
    end

    def same_film?(result, movie)
      return true if result.imdb_id.present? && result.imdb_id == movie.imdb_id
      return true if result.tmdb_id.present? && result.tmdb_id == movie.tmdb_id

      result.title.to_s.casecmp?(movie.title.to_s) && result.year == movie.year
    end
  end
end
