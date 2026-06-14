class Movie < ApplicationRecord
  has_many :comments, dependent: :destroy
  has_many :watch_histories, dependent: :destroy

  validates :title, presence: true

  scope :stale, -> { where("last_watched_at < ?", 1.month.ago).where.not(file_path: nil) }

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

  def self.find_by_natural_key(result)
    return find_by(imdb_id: result.imdb_id) if result.imdb_id.present? &&
                                               exists?(imdb_id: result.imdb_id)
    return find_by(tmdb_id: result.tmdb_id) if result.tmdb_id.present? &&
                                               exists?(tmdb_id: result.tmdb_id)

    nil
  end

  # Apply non-nil fields from a source result without clobbering data we already
  # have (a later source should only fill blanks), then save.
  def upsert_attributes_from_source(result)
    self.imdb_id ||= result.imdb_id
    self.tmdb_id ||= result.tmdb_id

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

  def genres_list
    genres.to_s.split(",").map(&:strip).reject(&:empty?)
  end

  # English subtitles plus the language of any other downloaded track. The real
  # files are produced by the video pipeline; here we expose what is available.
  def available_subtitles
    Array(subtitle_languages)
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
      comments_count: comments.count
    )
  end

  private

  # Placeholder until the streaming pipeline records real subtitle tracks.
  # Kept as a method so the API shape is already correct.
  def subtitle_languages
    []
  end
end
