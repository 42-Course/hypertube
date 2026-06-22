class Movie < ApplicationRecord
  has_many :comments, dependent: :destroy
  has_many :watch_histories, dependent: :destroy

  validates :title, presence: true

  scope :stale, -> { where("last_watched_at < ?", 1.month.ago).where.not(file_path: nil) }

  # A BitTorrent magnet URI built from the stored info-hash (magnet_hash), or
  # nil when no torrent has been resolved for this film yet. The streaming
  # service fetches metadata from the swarm, so the xt info-hash is sufficient.
  def magnet_uri
    return nil if magnet_hash.blank?

    "magnet:?xt=urn:btih:#{magnet_hash.downcase}"
  end

  # These operate purely on rows already persisted in our DB; the external
  # sources are only consulted by the search endpoint and the detail top-up.
  scope :title_matching,  ->(q) { where("title ILIKE ?", "%#{sanitize_sql_like(q)}%") }
  scope :with_genre,      ->(g) { where("genres ILIKE ?", "%#{sanitize_sql_like(g)}%") }
  scope :released_from,   ->(y) { where(year: y.to_i..) }
  scope :released_until,  ->(y) { where(year: ..y.to_i) }
  scope :rated_at_least,  ->(r) { where(rating: r.to_f..) }

  # Whitelist of user-facing sort keys -> real columns (guards against SQL
  # injection via the `sort` param and documents what is sortable).
  SORT_COLUMNS = { "name" => :title, "year" => :year,
                   "rating" => :rating, "popularity" => :popularity }.freeze

  # Apply the catalog filters supported by GET /movies and return a relation
  # (still chainable/paginatable). Blank filters are ignored.
  def self.filtered(query: nil, genre: nil, min_year: nil,
                    max_year: nil, min_rating: nil, sort: nil, order: nil)
    scope = all
    scope = scope.title_matching(query)      if query.present?
    scope = scope.with_genre(genre)          if genre.present?
    scope = scope.released_from(min_year)    if min_year.present?
    scope = scope.released_until(max_year)   if max_year.present?
    scope = scope.rated_at_least(min_rating) if min_rating.present?
    scope.sorted(sort, order)
  end

  # Order by a whitelisted column. Defaults to popularity; numeric/text columns
  # default to descending (most popular/highest first) and name to ascending,
  # unless an explicit order is given. NULLs sort last; id breaks ties so paging
  # is stable.
  def self.sorted(sort, order)
    column    = SORT_COLUMNS.fetch(sort.to_s, :popularity)
    descending = order.present? ? order.to_s.casecmp?("desc") : column != :title
    direction  = descending ? "DESC" : "ASC"
    order(Arel.sql("#{column} #{direction} NULLS LAST"), id: :asc)
  end

  # Attributes copied from an external MovieSources::Result.
  SOURCE_ATTRIBUTES = %i[title year rating cover_url summary genres duration
                         magnet_hash popularity].freeze

  # Find the local record for an external result (by whichever natural key the
  # source provided) or build a new one, then refresh its metadata. This is how
  # a freshly searched film gains a stable integer id and can hold comments.
  def self.upsert_from_source(result)
    movie = find_by_natural_key(result) || new
    movie.upsert_attributes_from_source(result)
    movie
  end

  # Prefer the tmdb_id match: identity resolution assigns canonical tmdb_ids, so
  # this lands on the canonical row rather than an older imdb-keyed duplicate.
  def self.find_by_natural_key(result)
    return find_by(tmdb_id: result.tmdb_id) if result.tmdb_id.present? &&
                                               exists?(tmdb_id: result.tmdb_id)
    return find_by(imdb_id: result.imdb_id) if result.imdb_id.present? &&
                                               exists?(imdb_id: result.imdb_id)

    nil
  end

  # Apply non-nil fields from a source result without clobbering data we already
  # have (a later source should only fill blanks), then save.
  def upsert_attributes_from_source(result)
    # imdb_id/tmdb_id are uniquely indexed. When the SAME film already exists
    # under a different natural key (e.g. an older imdb-keyed row and a newer
    # tmdb-keyed one), assigning the resolved id here would violate the unique
    # index, so only claim an id no other row owns.
    assign_natural_key(:imdb_id, result.imdb_id)
    assign_natural_key(:tmdb_id, result.tmdb_id)

    SOURCE_ATTRIBUTES.each do |attr|
      value = result[attr]
      next if value.nil? || value == ""

      self[attr] = value if self[attr].nil? || self[attr] == ""
    end

    save!
    self
  end

  def watched_by?(user)
    watch_histories.exists?(user: user)
  end

  # Idempotently mark this film as watched by `user`. Reuses an existing row so
  # a movie is never double-counted in someone's history; the create callback
  # bumps last_watched_at.
  def mark_watched_by(user)
    watch_histories.find_or_create_by!(user: user)
  end

  # Clear `user`'s watched mark(s) for this film. Idempotent (a no-op when the
  # user never watched it).
  def mark_unwatched_by(user)
    watch_histories.where(user: user).destroy_all
  end

  def genres_list
    genres.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  # English subtitles plus the language of any other downloaded track. The real
  # files are produced by the video pipeline; here we expose what is available.
  def available_subtitles
    Array(subtitle_languages)
  end

  # Cast/crew resolved from the metadata APIs (see MovieSources). `credits` is a
  # jsonb blob whose shape varies by source; these readers give the API a stable
  # surface. Cast members are { name, character?, profile_url? } hashes.
  def cast
    Array(credits["cast"])
  end

  def director
    credits["director"]
  end

  def producers
    Array(credits["producers"])
  end

  # Thumbnail payload for the library grid. `watched` is included only when we
  # know the viewer (authenticated requests).
  def as_thumbnail(user: nil)
    {
      id:        id,
      imdb_id:   imdb_id,
      title:     title,
      year:      year,
      rating:    rating,
      cover_url: cover_url,
      genres:    genres_list,
      watched:   user && watched_by?(user)
    }.compact
  end

  # Full detail payload (subject: name, id, imdb mark, year, length, available
  # subtitles, number of comments, plus summary/cover for the player page).
  def as_detail(user: nil)
    as_thumbnail(user: user).merge(
      summary:        summary,
      duration:       duration,
      subtitles:      available_subtitles,
      comments_count: comments.count,
      cast:           cast,
      director:       director,
      producers:      producers
    )
  end

  private

  # Set a uniquely-indexed natural key only when it is still blank here and not
  # already owned by another row, so enriching one film never collides with a
  # pre-existing duplicate that holds the same id under a different key.
  def assign_natural_key(attr, value)
    return if value.blank? || self[attr].present?
    return if Movie.where.not(id: id).exists?(attr => value)

    self[attr] = value
  end

  # Placeholder until the streaming pipeline records real subtitle tracks.
  # Kept as a method so the API shape is already correct.
  def subtitle_languages
    []
  end
end
