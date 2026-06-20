class Api::V1::UsersController < ApplicationController
  # Registration is public a user cannot hold a token before they exist.
  skip_before_action :doorkeeper_authorize!, only: %i[create]
  before_action :set_user, only: %i[show update movies]

  PER_PAGE = 20

  # GET /api/v1/users
  def index
    users = User.select(:id, :username)
    render json: users
  end

  # POST /api/v1/users public registration
  def create
    user = User.new(registration_params)

    if user.save
      render json: user.as_json(only: %i[id username email profile_picture_url]),
             status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/me current authenticated user's own full profile.
  def me
    render json: current_user.as_json(
      only: %i[id username email first_name last_name profile_picture_url preferred_language]
    )
  end

  # GET /api/v1/users/:id public profile (everything except the email).
  def show
    render json: @user.as_json(
      only: %i[id username first_name last_name preferred_language profile_picture_url]
    )
  end

  # PATCH /api/v1/users/:id
  #
  # Accepts multipart/form-data so an `avatar` image can be uploaded alongside
  # the editable profile fields. The avatar is stored via Active Storage and
  # surfaced through `profile_picture_url`.
  def update
    unless @user == current_user
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    if @user.update(user_params)
      render json: @user.as_json(
        only: %i[id username email first_name last_name preferred_language profile_picture_url]
      )
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/:id/movies
  #
  # The movies this user has watched, paginated (same shape as GET /movies).
  def movies
    scope  = @user.watched_movies.distinct.order("movies.created_at DESC")
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

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "User not found" }, status: :not_found
  end

  # The profile edit form is sent as multipart/form-data with flat fields
  # (username, avatar, ...). Accept that shape, and still tolerate a nested
  # `user` wrapper for JSON clients.
  def user_params
    source = params[:user].is_a?(ActionController::Parameters) ? params.require(:user) : params
    source.permit(:username, :email, :password,
                  :first_name, :last_name,
                  :preferred_language, :profile_picture_url, :avatar)
  end

  def registration_params
    params.require(:user).permit(:username, :email, :password,
                                 :first_name, :last_name,
                                 :preferred_language, :profile_picture_url)
  end

  def page
    [ params.fetch(:page, 1).to_i, 1 ].max
  end

  # Clamp per_page to a sane range so a client can't request the whole table.
  def per_page
    params.fetch(:per_page, PER_PAGE).to_i.clamp(1, 100)
  end
end
