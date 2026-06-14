module MovieSources
  # A normalized movie record produced by every source, so the aggregator can
  # merge TMDb, Prowlarr, etc. without caring where each field came from. Sources
  # leave unknown fields nil; the aggregator/model fill gaps from other sources.
  Result = Struct.new(
    :imdb_id,     # e.g. "tt1375666" (Prowlarr)
    :tmdb_id,     # e.g. 27205        (TMDb / Prowlarr)
    :title,
    :year,
    :rating,      # IMDb/TMDb 0-10 score
    :cover_url,
    :summary,
    :genres,      # comma-separated string, e.g. "Action, Sci-Fi"
    :duration,    # minutes
    :magnet_hash, # best torrent info-hash (video source only)
    :popularity,  # source-specific score used to rank the front page
    keyword_init: true
  ) do
    # Key used to dedupe the same film coming from two sources. We prefer the
    # external ids: TMDb supplies tmdb_id and Prowlarr releases carry both
    # tmdb_id and imdb_id, so an id is the most reliable shared identifier.
    # Prowlarr's raw release names ("Inception.2010.1080p…") make title+year a
    # poor key, so it is only the last resort when no id is present.
    def dedupe_key
      return "tmdb:#{tmdb_id}" if tmdb_id.present?
      return "imdb:#{imdb_id}" if imdb_id.present?
      return "title:#{title.downcase.strip}:#{year}" if title.present? && year.present?

      "title:#{title.to_s.downcase.strip}"
    end

    # Merge another result into this one, keeping existing non-nil values and
    # filling blanks from the other. `self` wins on conflicts (call order sets
    # precedence, the aggregator lists the richer source first).
    def merge(other)
      to_h.each do |key, value|
        self[key] = other[key] if value.nil? || value == ""
      end
      self
    end
  end
end
