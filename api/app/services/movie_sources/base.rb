module MovieSources
  # Shared behaviour for every external movie source.
  #
  # Subclasses implement #search and #popular, returning an Array of
  # MovieSources::Result. They use #get_json for HTTP so that a flaky or
  # unreachable source degrades to an empty list instead of breaking the page.
  class Base
    # Movie listings barely change hour to hour, so we memoize each source's
    # raw responses in Redis to avoid hammering the external APIs (and to stay
    # well under their rate limits).
    CACHE_TTL = 1.hour

    # @param query [String] free-text search term
    # @param page  [Integer] 1-based page number
    # @return [Array<MovieSources::Result>]
    def search(query:, page: 1)
      raise NotImplementedError, "#{self.class} must implement #search"
    end

    # Front-page feed when the user has not searched yet.
    # @return [Array<MovieSources::Result>]
    def popular(page: 1)
      raise NotImplementedError, "#{self.class} must implement #popular"
    end

    # Whether this source is usable (e.g. an API key is configured).
    # Sources without a key return false so the aggregator can skip them.
    def available?
      true
    end

    private

    # Cached GET+parse. Only successful, non-empty responses are written to the
    # cache, so a transient failure is never memoized for an hour.
    def get_json(url, params = {})
      key    = cache_key(url, params)
      cached = Rails.cache.read(key)
      Rails.logger.info("[MovieSources] Lucky you! #{key} is cached!") if cached
      return cached if cached

      body = fetch_json(url, params)
      Rails.cache.write(key, body, expires_in: CACHE_TTL) if body.present?
      body
    end

    # Perform a GET and parse JSON, returning {} on any failure. Network and
    # parse errors are swallowed here so one bad source never breaks search.
    def fetch_json(url, params)
      response = connection.get(url, params)
      return {} unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("[MovieSources] #{self.class}: #{e.class} #{e.message}")
      {}
    end

    # Stable cache key per source + endpoint + params. The API key is excluded
    # so it never lands in Redis and does not affect cache hits.
    def cache_key(url, params)
      stable = params.transform_keys(&:to_s).except("api_key").sort.to_h
      digest = Digest::SHA256.hexdigest(stable.to_json)
      "movie_sources:#{self.class.name}:#{url}:#{digest}"
    end

    def connection
      @connection ||= Faraday.new(url: self.class::BASE_URL) do |f|
        f.options.timeout      = 5
        f.options.open_timeout = 3
        f.headers["Accept"]    = "application/json"
      end
    end
  end
end
