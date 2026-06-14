class Api::V1::MoviesController < ApplicationController
  # The catalog and search are public (subject: "Any user can access the
  # website's front page"). Movie details require authentication.
  skip_before_action :doorkeeper_authorize!, only: %i[index search]

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
      per_page:   PER_PAGE,
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
    render json: movie.as_detail(user: current_user)
  end

  private

  def page
    [ params.fetch(:page, 1).to_i, 1 ].max
  end

  # Clamp per_page to a sane range so a client can't request the whole table.
  def per_page
    requested = params.fetch(:per_page, PER_PAGE).to_i
    requested.clamp(1, 100)
  end
end
