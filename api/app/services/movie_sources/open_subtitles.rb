# frozen_string_literal: true

require "faraday"
require "json"

module MovieSources
  # OpenSubtitles (REST API v1) client used to offer downloadable subtitles for a
  # movie, keyed by its IMDb id. Requires OPEN_SUBTITLES_API_KEY; without it the
  # source reports itself unavailable and the controller simply returns no
  # languages (the streaming pipeline still exposes embedded/in-torrent subs).
  #
  # Two-step flow per OpenSubtitles: GET /subtitles?imdb_id=... lists matches,
  # then POST /download exchanges a file_id for a temporary download link, which
  # we fetch and convert from SRT to WebVTT for the browser overlay.
  # Docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api
  class OpenSubtitles
    BASE_URL  = "https://api.opensubtitles.com/api/v1/"
    CACHE_TTL = 6.hours

    def available?
      api_key.present?
    end

    # Subtitle languages available for this movie, restricted to `language` (the
    # viewer's preferred language). We deliberately fetch only that one language
    # rather than every language, to respect the OpenSubtitles download quota.
    # Returns [language] when something is available, otherwise [].
    def languages(movie, language:)
      results(movie, language).filter_map { |item| item.dig("attributes", "language") }.uniq.sort
    end

    # WebVTT string for the (preferred) language, or nil when unavailable. Result
    # is cached because producing it costs an OpenSubtitles download quota credit.
    def vtt(movie, language)
      return nil unless available? && language.present?

      match = results(movie, language).find { |item| item.dig("attributes", "language") == language }
      file_id = match&.dig("attributes", "files", 0, "file_id")
      return nil unless file_id

      cache_key = "open_subtitles:vtt:#{file_id}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      srt = download_srt(file_id)
      return nil if srt.blank?

      vtt = SrtToVtt.convert(srt)
      Rails.cache.write(cache_key, vtt, expires_in: CACHE_TTL)
      vtt
    end

    private

    # The /subtitles search results for this movie's imdb id, scoped to a single
    # language (cached per imdb+language).
    def results(movie, language)
      imdb = imdb_number(movie)
      return [] unless available? && imdb && language.present?

      cache_key = "open_subtitles:search:#{imdb}:#{language}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      body = search_request(imdb, language)
      data = body.is_a?(Hash) ? Array(body["data"]) : []
      Rails.cache.write(cache_key, data, expires_in: CACHE_TTL) if data.present?
      data
    end

    def search_request(imdb, language)
      response = connection.get("subtitles") do |req|
        req.params["imdb_id"] = imdb
        req.params["languages"] = language
        req.params["order_by"] = "download_count"
      end
      return {} unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("[OpenSubtitles] search: #{e.class} #{e.message}")
      {}
    end

    def download_srt(file_id)
      response = connection.post("download") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(file_id: file_id)
      end
      return nil unless response.success?

      link = JSON.parse(response.body)["link"]
      return nil if link.blank?

      file = Faraday.get(link)
      file.success? ? file.body : nil
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("[OpenSubtitles] download: #{e.class} #{e.message}")
      nil
    end

    # OpenSubtitles expects the numeric IMDb id (no "tt" prefix, no leading zeros).
    def imdb_number(movie)
      raw = movie.imdb_id.to_s.strip
      return nil if raw.empty?

      digits = raw.delete_prefix("tt").sub(/\A0+/, "")
      digits.empty? ? nil : digits
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.options.timeout      = 8
        f.options.open_timeout = 4
        f.headers["Api-Key"]    = api_key.to_s
        f.headers["Accept"]     = "application/json"
        f.headers["User-Agent"] = ENV.fetch("OPEN_SUBTITLES_USER_AGENT", "Hypertube v1.0")
      end
    end

    def api_key
      ENV["OPEN_SUBTITLES_API_KEY"].presence
    end
  end
end
