class Api::V1::MoviesController < ApplicationController
  # The catalog and search are public (subject: "Any user can access the
  # website's front page"). Movie details require authentication.
  skip_before_action :doorkeeper_authorize!, only: %i[index search]
  before_action :set_movie, only: %i[mark_watched mark_unwatched subtitles subtitle update_duration]

  PER_PAGE = 20

  # GET /api/v1/movies
  #
  # The local library: movies already saved in our DB (every film anyone has
  # ever searched/opened). Pure DB query fast, paginated, filterable, and
  # never touches the external sources. Use GET /movies/search to discover new
  # films from TMDb/Prowlarr.
  #
  # Params: query (title), genre, min_year, max_year, min_rating,
  #         sort (name|year|rating|popularity), order (asc|desc), page, per_page.
  def index
    scope = Movie.filtered(
      query:      params[:query].presence,
      genre:      params[:genre].presence,
      min_year:   params[:min_year].presence,
      max_year:   params[:max_year].presence,
      min_rating: params[:min_rating].presence,
      sort:       params[:sort],
      order:      params[:order]
    )

    total  = scope.count
    movies = scope.limit(per_page).offset((page - 1) * per_page)

    render json: {
      page:        page,
      per_page:    per_page,
      total:       total,
      total_pages: (total.to_f / per_page).ceil,
      movies:      movies.map { |movie| movie.as_thumbnail(user: current_user) }
    }
  end

  # GET /api/v1/movies/search
  #
  # Discovery: queries the external sources (TMDb metadata + Prowlarr torrents),
  # persists each film locally (so it gains a stable id and can hold comments),
  # then sorts/filters/paginates. With no `query` it returns the most popular
  # films; with a `query` it searches, sorted by name. Slower than #index since
  # it makes network calls, so its responses are cached (see MovieSources::Base).
  #
  # Params: query, page, sort (name|year|rating|genre|popularity), order
  #         (asc|desc), genre, min_year, max_year, min_rating.
  def search
    movies = MovieSources::Aggregator.new.list(
      query:      params[:query].presence,
      page:       page,
      per_page:   params[:per_page].presence.to_i,
      sort:       params[:sort],
      order:      params[:order],
      genre:      params[:genre].presence,
      min_year:   params[:min_year].presence,
      max_year:   params[:max_year].presence,
      min_rating: params[:min_rating].presence
    )

    render json: {
      page:   page,
      movies: movies.map { |movie| movie.as_thumbnail(user: current_user) }
    }
  end

  # GET /api/v1/movies/:id
  #
  # Full details for a single (already-discovered) movie. Tops up missing
  # metadata from the external sources on first view.
  def show
    movie = Movie.find_by(id: params[:id])
    return render json: { error: "Movie not found" }, status: :not_found unless movie

    MovieSources::Aggregator.new.enrich(movie)
    ensure_subtitle_languages(movie)
    render json: movie.as_detail(user: current_user)
  end

  # POST /api/v1/movies/:id/stream_ticket
  #
  # Resolve the movie to a streaming media (movie -> magnet -> media, which also
  # starts the torrent download), then mint a short-lived ticket bound to that
  # media. The browser hands the ticket directly to the streaming service, which
  # verifies it locally with the shared secret (StreamTicket), so the user's API
  # token never crosses into the streaming boundary.
  def stream_ticket
    movie = Movie.find_by(id: params[:id])
    return render json: { error: "Movie not found" }, status: :not_found unless movie

    magnet = movie.magnet_uri
    if magnet.blank?
      return render json: { error: "no_torrent", message: "No torrent is available for this movie yet" },
                    status: :unprocessable_entity
    end

    media_id = StreamingService.new.ensure_media(magnet: magnet)
    # Remember the media id so the streaming service's download-complete callback
    # can map a finished media back to this movie.
    movie.update_column(:media_id, media_id) if movie.media_id != media_id
    ticket   = StreamTicket.issue(user: current_user, movie: movie, media_id: media_id)

    render json: {
      ticket:        ticket,
      token_type:    "Bearer",
      expires_in:    StreamTicket::TTL.to_i,
      media_id:      media_id,
      streaming_url: StreamingService.public_base_url
    }, status: :created
  rescue StreamingService::Error => e
    render json: { error: "streaming_unavailable", message: e.message }, status: :bad_gateway
  end

  # POST /api/v1/movies/:id/watched
  #
  # Mark this movie as watched by the current user. Idempotent: marking an
  # already-watched film is a no-op. Returns the refreshed detail payload so the
  # client sees watched: true.
  def mark_watched
    @movie.mark_watched_by(current_user)
    render json: @movie.as_detail(user: current_user)
  end

  # DELETE /api/v1/movies/:id/watched
  #
  # Clear the current user's watched mark for this movie. Idempotent.
  def mark_unwatched
    @movie.mark_unwatched_by(current_user)
    render json: @movie.as_detail(user: current_user)
  end

  # GET /api/v1/movies/:id/subtitles
  #
  # Subtitle languages available from OpenSubtitles for this movie (cached on the
  # row). The browser overlays the chosen one as a <track>.
  def subtitles
    render json: { languages: ensure_subtitle_languages(@movie) }
  end

  # GET /api/v1/movies/:id/subtitles/:language
  #
  # Serve the chosen OpenSubtitles language as WebVTT (converted from SRT). The
  # SPA fetches this with its bearer token and hands it to a <track> via a blob.
  def subtitle
    vtt = MovieSources::OpenSubtitles.new.vtt(@movie, params[:language])
    if vtt.blank?
      return render json: { error: "subtitle_unavailable" }, status: :not_found
    end

    render plain: vtt, content_type: "text/vtt"
  end

  # PATCH /api/v1/movies/:id/duration
  #
  # Persist the movie runtime discovered from the torrent/transcoder (in seconds;
  # stored as whole minutes). Metadata sources almost always leave duration empty,
  # so this fills it in. Only sets it when still blank, to avoid clobbering a
  # value an external source did provide.
  def update_duration
    seconds = params[:seconds].to_i
    if seconds.positive? && @movie.duration.blank?
      @movie.update!(duration: (seconds / 60.0).round)
    end
    render json: @movie.as_detail(user: current_user)
  end

  private

  # Fetch-and-cache the OpenSubtitles language list for a movie. Cached on the
  # row so the detail endpoint does not make an external call on every view.
  def ensure_subtitle_languages(movie)
    return movie.available_subtitles if movie.available_subtitles.present?

    languages = MovieSources::OpenSubtitles.new.languages(movie)
    movie.update_column(:subtitle_languages, languages) if languages.present?
    languages
  end

  def set_movie
    @movie = Movie.find_by(id: params[:id])
    render json: { error: "Movie not found" }, status: :not_found unless @movie
  end

  def page
    [ params.fetch(:page, 1).to_i, 1 ].max
  end

  # Clamp per_page to a sane range so a client can't request the whole table.
  def per_page
    requested = params.fetch(:per_page, PER_PAGE).to_i
    requested.clamp(1, 100)
  end
end
