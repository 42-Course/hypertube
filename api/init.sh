#!/bin/bash
set -e

STEP=0
total=7

step() {
  STEP=$((STEP + 1))
  printf "\n\033[1;34m[%d/%d] %s\033[0m\n" "$STEP" "$total" "$1"
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       Hypertube API – First-time Setup       ║"
echo "╚══════════════════════════════════════════════╝"

# ─── 1. Generate Rails API app ───────────────────────────────────────────────
step "Generating Rails API application"
if [ ! -f "config/application.rb" ]; then
  # Bootstrap Gemfile only has `gem 'rails'`. Install it into the /gems volume
  # first so the `rails` binary exists before we call `rails new`.
  echo "  Installing bootstrap gems..."
  bundle install

  bundle exec rails new . \
    --api \
    --database=postgresql \
    --skip-test \
    --skip-bundle \
    --skip-git \
    --force
  echo "  Rails application generated."

else
  echo "  Rails app already present – skipping rails new."
fi

# Patch swagger_helper.rb for our API structure
if [ -f "spec/swagger_helper.rb" ]; then
  cat > spec/swagger_helper.rb << 'SWAGGER_HELPER'
require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Hypertube API",
        version: "v1",
        description: "RESTful API with OAuth2 authentication for the Hypertube video platform"
      },
      components: {
        securitySchemes: {
          oauth2: {
            type: :oauth2,
            flows: {
              password: {
                tokenUrl: "/oauth/token",
                scopes: {}
              }
            }
          }
        }
      },
      security: [{ oauth2: [] }],
      servers: [
        { url: ENV.fetch("API_URL", "http://localhost:3000"), description: "Development" }
      ]
    }
  }

  config.openapi_format = :yaml
end
SWAGGER_HELPER
  echo "  swagger_helper.rb configured."
fi

# ─── 6. Create stub controllers ──────────────────────────────────────────────
step "Creating stub API controllers"

mkdir -p app/controllers/api/v1

# Users controller
if [ ! -f "app/controllers/api/v1/users_controller.rb" ]; then
  cat > app/controllers/api/v1/users_controller.rb << 'USERS_CTRL'
class Api::V1::UsersController < ApplicationController
  before_action :set_user, only: %i[show update]

  # GET /api/v1/users
  def index
    users = User.select(:id, :username)
    render json: users
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
end
USERS_CTRL
  echo "  users_controller.rb created."
fi

# Movies controller
if [ ! -f "app/controllers/api/v1/movies_controller.rb" ]; then
  cat > app/controllers/api/v1/movies_controller.rb << 'MOVIES_CTRL'
class Api::V1::MoviesController < ApplicationController
  skip_before_action :doorkeeper_authorize!, only: %i[index]

  # GET /api/v1/movies  — public: returns top movies for the front page
  def index
    render json: { movies: [], message: "TODO: integrate external torrent sources" }
  end

  # GET /api/v1/movies/:id
  def show
    render json: { movie: {}, message: "TODO: fetch movie details" }
  end
end
MOVIES_CTRL
  echo "  movies_controller.rb created."
fi

# Comments controller
if [ ! -f "app/controllers/api/v1/comments_controller.rb" ]; then
  cat > app/controllers/api/v1/comments_controller.rb << 'COMMENTS_CTRL'
class Api::V1::CommentsController < ApplicationController
  before_action :set_comment, only: %i[show update destroy]

  # GET /api/v1/comments
  def index
    comments = Comment.order(created_at: :desc).limit(50)
    render json: comments.as_json(only: %i[id content created_at],
                                  include: { user: { only: %i[id username] } })
  end

  # GET /api/v1/comments/:id
  def show
    render json: @comment.as_json(only: %i[id content created_at],
                                  include: { user: { only: %i[id username] } })
  end

  # POST /api/v1/comments  OR  POST /api/v1/movies/:movie_id/comments
  def create
    comment = current_user.comments.build(comment_params)
    comment.movie_id = params[:movie_id] if params[:movie_id]

    if comment.save
      render json: comment, status: :created
    else
      render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/comments/:id
  def update
    unless @comment.user == current_user
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    if @comment.update(comment_params)
      render json: @comment
    else
      render json: { errors: @comment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/comments/:id
  def destroy
    unless @comment.user == current_user
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    @comment.destroy
    head :no_content
  end

  private

  def set_comment
    @comment = Comment.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Comment not found" }, status: :not_found
  end

  def comment_params
    params.require(:comment).permit(:content, :movie_id)
  end
end
COMMENTS_CTRL
  echo "  comments_controller.rb created."
fi

# ─── 7. Database setup ───────────────────────────────────────────────────────
step "Setting up the database"
bundle exec rails db:create && echo "  Database created." || echo "  Database may already exist – continuing."

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✓  Hypertube API bootstrap complete!                   ║"
echo "║                                                          ║"
echo "║  Next steps:                                             ║"
echo "║    make up       – Start all services                   ║"
echo "║    make migrate  – Run any pending migrations            ║"
echo "║    make console  – Open the Rails console                ║"
echo "║    make test     – Run the test suite                    ║"
echo "║                                                          ║"
echo "║  API docs available at: http://localhost:3000/api-docs   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
