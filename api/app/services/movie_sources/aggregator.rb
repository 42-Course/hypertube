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

    # @param sources          discovery sources queried for search/popular.
    # @param resolver          metadata API used to give sparse releases a
    #                          canonical identity + poster/summary (TMDb).
    # @param credit_providers  cast/crew providers tried in order on the detail
    #                          view (TMDb for photos/characters, OMDb/IMDb next).
    def initialize(sources: nil, resolver: nil, credit_providers: nil)
      @sources          = sources          || [ Tmdb.new, Prowlarr.new ]
      @resolver         = resolver         || Tmdb.new
      @credit_providers = credit_providers || [ Tmdb.new, Omdb.new ]
    end

    # @return [Array<Movie>] persisted, filtered, sorted, paginated.
    def list(query: nil, page: 1, per_page: 20, **filters)
      results = collect(query: query, page: page)
      # Raw Prowlarr releases ("TPB.AFK.2013.1080p...") arrive with a magnet but
      # no poster/ids, and their messy names each dedupe differently - so the
      # same film shows up as many thumbnail-less cards. Resolve each sparse
      # release against the metadata API by title FIRST: it gains a canonical
      # poster/summary AND a tmdb_id, so #merge then folds the duplicates into
      # one real movie. Results that already carry metadata cost nothing.
      results = results.map { |result| resolve_identity(result) }
      movies  = merge(results).map { |result| Movie.upsert_from_source(result) }
      movies  = apply_filters(movies, **filters.slice(:genre, :min_year, :max_year, :min_rating))
      movies  = apply_sort(movies, query: query, sort: filters[:sort], order: filters[:order])
      movies.first(per_page)
    end

    # Best-effort top-up for a single movie shown on its detail page. Reaches out
    # only for the gaps that remain and never raises. Three independent gaps:
    #
    #   * display metadata (summary/cover) - resolved from the metadata API by
    #     title.
    #   * the streaming magnet - resolved from Prowlarr, looking for a
    #     magnet-BEARING match explicitly rather than the first title match
    #     (usually the magnet-less TMDb result). This is why a film can have rich
    #     metadata yet no magnet until opened, and why we retry while it is blank.
    #   * cast/crew - fetched lazily (TMDb credits, OMDb/IMDb fallback) the first
    #     time the film is opened.
    def enrich(movie)
      return movie if movie.title.blank?

      backfill_metadata(movie) if movie.summary.blank? || movie.cover_url.blank?
      resolve_magnet(movie)    if movie.magnet_hash.blank?
      resolve_credits(movie)   if movie.credits.blank?
      movie
    end

    private

    # Give a sparse discovery result (a Prowlarr-only release: a magnet + a messy
    # title, no poster/ids) a canonical identity by matching its title against
    # the metadata API. Returns the rich match with the release's magnet folded
    # in, so duplicates collapse in #merge. Results that already have an id or a
    # poster are returned untouched (no network call).
    def resolve_identity(result)
      return result if result.tmdb_id.present? || result.cover_url.present?

      match = best_title_match(result.title, result.year)
      match ? match.merge(result) : result
    end

    # Top up a persisted movie's display metadata from the metadata API by title.
    def backfill_metadata(movie)
      match = best_title_match(movie.title, movie.year)
      movie.upsert_attributes_from_source(match) if match
    end

    # Best metadata-API match for a title: prefer the same release year, else the
    # top result. Never raises (a flaky source must not break the page).
    def best_title_match(title, year)
      return nil if title.blank? || !@resolver.available?

      candidates = @resolver.search(query: title)
      candidates.find { |candidate| candidate.year == year } || candidates.first
    rescue StandardError => e
      Rails.logger.warn("[MovieSources] resolver #{@resolver.class}: #{e.class} #{e.message}")
      nil
    end

    # Find a magnet for a film from the discovery sources (Prowlarr).
    def resolve_magnet(movie)
      candidates = merge(collect(query: movie.title, page: 1))
      magnet = candidates.find { |r| r.magnet_hash.present? && same_film?(r, movie) }
      movie.upsert_attributes_from_source(magnet) if magnet
    end

    # Fetch cast/crew from the first credit provider that has data (TMDb by
    # tmdb_id, then OMDb by imdb_id). Stored as a jsonb blob on the movie.
    def resolve_credits(movie)
      credits = @credit_providers.select(&:available?).lazy
                                 .filter_map { |provider| safe_credits(provider, movie) }
                                 .first
      movie.update!(credits: credits) if credits.present?
    end

    def safe_credits(provider, movie)
      provider.credits(movie)
    rescue StandardError => e
      Rails.logger.warn("[MovieSources] credits #{provider.class}: #{e.class} #{e.message}")
      nil
    end

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
