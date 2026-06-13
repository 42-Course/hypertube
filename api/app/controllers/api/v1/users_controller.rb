class Api::V1::UsersController < ApplicationController
  # Registration is public — a user cannot hold a token before they exist.
  skip_before_action :doorkeeper_authorize!, only: %i[create]
  before_action :set_user, only: %i[show update]

  # GET /api/v1/users
  def index
    users = User.select(:id, :username)
    render json: users
  end

  # POST /api/v1/users — public registration
  def create
    user = User.new(registration_params)

    if user.save
      render json: user.as_json(only: %i[id username email profile_picture_url]),
             status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/:id
  def show
    render json: @user.as_json(only: %i[id username profile_picture_url])
  end

  # PATCH /api/v1/users/:id
  def update
    unless @user == current_user
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    if @user.update(user_params)
      render json: @user.as_json(only: %i[id username email profile_picture_url])
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "User not found" }, status: :not_found
  end

  def user_params
    params.require(:user).permit(:username, :email, :password, :profile_picture_url)
  end

  def registration_params
    params.require(:user).permit(:username, :email, :password,
                                 :first_name, :last_name,
                                 :preferred_language, :profile_picture_url)
  end
end
