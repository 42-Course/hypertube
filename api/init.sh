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

  # Rails 8 generates its own Dockerfile (production multi-stage build).
  # Rename it so it coexists with our Dockerfile.dev (used by docker-compose).
  if [ -f "Dockerfile" ]; then
    mv Dockerfile Dockerfile.production
    echo "  Renamed Rails-generated Dockerfile → Dockerfile.production"
  fi
else
  echo "  Rails app already present – skipping rails new."
fi

# # ─── 2. Patch Gemfile ────────────────────────────────────────────────────────
# step "Patching Gemfile with project gems"
# if ! grep -q "rspec-rails" Gemfile 2>/dev/null; then
#   cat >> Gemfile << 'EXTRA_GEMS'

# # ── Authentication ────────────────────────────────────────────────────────────
# gem "devise", "~> 4.9"
# gem "devise-jwt", "~> 0.11"
# gem "omniauth", "~> 2.1"
# gem "omniauth-oauth2", "~> 1.8"
# gem "omniauth-rails_csrf_protection"

# # ── OAuth2 provider (token endpoint) ─────────────────────────────────────────
# gem "doorkeeper", "~> 5.7"

# # ── API Documentation (Swagger / OpenAPI) ────────────────────────────────────
# gem "rswag-api"
# gem "rswag-ui"

# # ── Cross-Origin Resource Sharing ────────────────────────────────────────────
# gem "rack-cors"

# # ── Background processing ─────────────────────────────────────────────────────
# gem "sidekiq", "~> 7.0"

# # ── HTTP client for external sources (YIFY, YTS, etc.) ───────────────────────
# gem "faraday", "~> 2.0"

# # ── File attachments (profile pictures) ──────────────────────────────────────
# # Active Storage is included in Rails – no extra gem needed

# group :development, :test do
#   gem "rspec-rails", "~> 6.1"
#   gem "factory_bot_rails"
#   gem "faker"
#   gem "database_cleaner-active_record"
#   gem "shoulda-matchers", "~> 6.0"
#   gem "simplecov", require: false
#   gem "simplecov-lcov", require: false
#   gem "rswag-specs"
# end
# EXTRA_GEMS
#   echo "  Gems appended."
# else
#   echo "  Gems already patched – skipping."
# fi

# # ─── 3. Bundle install ───────────────────────────────────────────────────────
# step "Installing gems (may take a few minutes on first run)"
# bundle install
# echo "  All gems installed."

# # ─── 4. Write configuration files ───────────────────────────────────────────
# step "Writing configuration files"

# # database.yml — reads every credential from env vars
# cat > config/database.yml << 'DATABASE_YML'
# default: &default
#   adapter: postgresql
#   encoding: unicode
#   pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
#   host: <%= ENV.fetch("DATABASE_HOST") { "db" } %>
#   port: <%= ENV.fetch("DATABASE_PORT") { 5432 } %>
#   username: <%= ENV.fetch("DATABASE_USERNAME") { "postgres" } %>
#   password: <%= ENV.fetch("DATABASE_PASSWORD") { "password" } %>

# development:
#   <<: *default
#   database: <%= ENV.fetch("DATABASE_NAME") { "hypertube_development" } %>

# test:
#   <<: *default
#   database: hypertube_test

# production:
#   <<: *default
#   database: <%= ENV.fetch("DATABASE_NAME") { "hypertube_production" } %>
# DATABASE_YML

# # CORS — allow requests from the React frontend
# cat > config/initializers/cors.rb << 'CORS_RB'
# Rails.application.config.middleware.insert_before 0, Rack::Cors do
#   allow do
#     origins ENV.fetch("FRONTEND_URL", "http://localhost:5173")

#     resource "*",
#       headers: :any,
#       methods: %i[get post put patch delete options head],
#       expose: ["Authorization"],
#       max_age: 600
#   end
# end
# CORS_RB

# # Routes — API v1 namespace + Doorkeeper + Swagger UI
# cat > config/routes.rb << 'ROUTES_RB'
# Rails.application.routes.draw do
#   use_doorkeeper

#   mount Rswag::Ui::Engine => "/api-docs"
#   mount Rswag::Api::Engine => "/api-docs"

#   namespace :api do
#     namespace :v1 do
#       resources :users, only: %i[index show update]

#       resources :movies, only: %i[index show] do
#         resources :comments, only: %i[create]
#       end

#       resources :comments, only: %i[index show update destroy]
#     end
#   end
# end
# ROUTES_RB

# # Application controller — require a valid Doorkeeper token by default
# cat > app/controllers/application_controller.rb << 'APP_CTRL'
# class ApplicationController < ActionController::API
#   before_action :doorkeeper_authorize!

#   private

#   def current_user
#     @current_user ||= User.find(doorkeeper_token.resource_owner_id) if doorkeeper_token
#   end
# end
# APP_CTRL

# echo "  Configuration files written."

# # ─── 5. Run Rails generators ─────────────────────────────────────────────────
# step "Running Rails generators"

# run_generator() {
#   if bundle exec rails generate "$@" 2>&1 | grep -q "conflict\|already exists\|identical"; then
#     echo "  (skipped – $1 already generated)"
#   else
#     echo "  Generated: $1"
#   fi
# }

# bundle exec rails generate rspec:install   2>/dev/null && echo "  rspec:install done"     || echo "  rspec already set up"
# bundle exec rails generate rswag:install   2>/dev/null && echo "  rswag:install done"     || echo "  rswag already set up"
# bundle exec rails generate devise:install  2>/dev/null && echo "  devise:install done"    || echo "  devise already set up"
# bundle exec rails generate doorkeeper:install 2>/dev/null && echo "  doorkeeper:install done" || echo "  doorkeeper already set up"

# # Prepend SimpleCov to spec/spec_helper.rb
# if [ -f "spec/spec_helper.rb" ] && ! grep -q "SimpleCov" spec/spec_helper.rb; then
#   TMPFILE=$(mktemp)
#   cat > "$TMPFILE" << 'SIMPLECOV_HEADER'
# require "simplecov"
# require "simplecov-lcov"

# if ENV["COVERAGE"]
#   SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
#     SimpleCov::Formatter::HTMLFormatter,
#     SimpleCov::Formatter::LcovFormatter,
#   ])
# end

# SimpleCov.start "rails" do
#   enable_coverage :branch
#   add_filter "/spec/"
#   add_filter "/config/"
#   add_group "Controllers", "app/controllers"
#   add_group "Models",      "app/models"
#   add_group "Services",    "app/services"
# end

# SIMPLECOV_HEADER
#   cat spec/spec_helper.rb >> "$TMPFILE"
#   mv "$TMPFILE" spec/spec_helper.rb
#   echo "  SimpleCov prepended to spec/spec_helper.rb"
# fi

# # Configure shoulda-matchers + factory_bot in rails_helper
# if [ -f "spec/rails_helper.rb" ] && ! grep -q "Shoulda::Matchers" spec/rails_helper.rb; then
#   cat >> spec/rails_helper.rb << 'RAILS_HELPER_ADDONS'

# Shoulda::Matchers.configure do |config|
#   config.integrate do |with|
#     with.test_framework :rspec
#     with.library :rails
#   end
# end

# RSpec.configure do |config|
#   config.include FactoryBot::Syntax::Methods
# end
# RAILS_HELPER_ADDONS
#   echo "  shoulda-matchers + factory_bot configured in rails_helper.rb"
# fi

# # Patch swagger_helper.rb for our API structure
# if [ -f "spec/swagger_helper.rb" ]; then
#   cat > spec/swagger_helper.rb << 'SWAGGER_HELPER'
# require "rails_helper"

# RSpec.configure do |config|
#   config.swagger_root = Rails.root.join("swagger").to_s

#   config.swagger_docs = {
#     "v1/swagger.yaml" => {
#       openapi: "3.0.1",
#       info: {
#         title: "Hypertube API",
#         version: "v1",
#         description: "RESTful API with OAuth2 authentication for the Hypertube video platform"
#       },
#       components: {
#         securitySchemes: {
#           oauth2: {
#             type: :oauth2,
#             flows: {
#               password: {
#                 tokenUrl: "/oauth/token",
#                 scopes: {}
#               }
#             }
#           }
#         }
#       },
#       security: [{ oauth2: [] }],
#       servers: [
#         { url: ENV.fetch("API_URL", "http://localhost:3000"), description: "Development" }
#       ]
#     }
#   }

#   config.swagger_format = :yaml
# end
# SWAGGER_HELPER
#   echo "  swagger_helper.rb configured."
# fi

# # ─── 6. Create stub controllers ──────────────────────────────────────────────
# step "Creating stub API controllers"

# mkdir -p app/controllers/api/v1

# # Users controller
# if [ ! -f "app/controllers/api/v1/users_controller.rb" ]; then
#   cat > app/controllers/api/v1/users_controller.rb << 'USERS_CTRL'
# class Api::V1::UsersController < ApplicationController
#   before_action :set_user, only: %i[show update]

#   # GET /api/v1/users
#   def index
#     users = User.select(:id, :username)
#     render json: users
#   end

#   # GET /api/v1/users/:id
#   def show
#     render json: @user.as_json(only: %i[id username profile_picture_url])
#   end

#   # PATCH /api/v1/users/:id
#   def update
#     unless @user == current_user
#       return render json: { error: "Forbidden" }, status: :forbidden
#     end

#     if @user.update(user_params)
#       render json: @user.as_json(only: %i[id username email profile_picture_url])
#     else
#       render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
#     end
#   end

#   private

#   def set_user
#     @user = User.find(params[:id])
#   rescue ActiveRecord::RecordNotFound
#     render json: { error: "User not found" }, status: :not_found
#   end

#   def user_params
#     params.require(:user).permit(:username, :email, :password, :profile_picture_url)
#   end
# end
# USERS_CTRL
#   echo "  users_controller.rb created."
# fi

# # Movies controller
# if [ ! -f "app/controllers/api/v1/movies_controller.rb" ]; then
#   cat > app/controllers/api/v1/movies_controller.rb << 'MOVIES_CTRL'
# class Api::V1::MoviesController < ApplicationController
#   skip_before_action :doorkeeper_authorize!, only: %i[index]

#   # GET /api/v1/movies  — public: returns top movies for the front page
#   def index
#     render json: { movies: [], message: "TODO: integrate external torrent sources" }
#   end

#   # GET /api/v1/movies/:id
#   def show
#     render json: { movie: {}, message: "TODO: fetch movie details" }
#   end
# end
# MOVIES_CTRL
#   echo "  movies_controller.rb created."
# fi

# # Comments controller
# if [ ! -f "app/controllers/api/v1/comments_controller.rb" ]; then
#   cat > app/controllers/api/v1/comments_controller.rb << 'COMMENTS_CTRL'
# class Api::V1::CommentsController < ApplicationController
#   before_action :set_comment, only: %i[show update destroy]

#   # GET /api/v1/comments
#   def index
#     comments = Comment.order(created_at: :desc).limit(50)
#     render json: comments.as_json(only: %i[id content created_at],
#                                   include: { user: { only: %i[id username] } })
#   end

#   # GET /api/v1/comments/:id
#   def show
#     render json: @comment.as_json(only: %i[id content created_at],
#                                   include: { user: { only: %i[id username] } })
#   end

#   # POST /api/v1/comments  OR  POST /api/v1/movies/:movie_id/comments
#   def create
#     comment = current_user.comments.build(comment_params)
#     comment.movie_id = params[:movie_id] if params[:movie_id]

#     if comment.save
#       render json: comment, status: :created
#     else
#       render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
#     end
#   end

#   # PATCH /api/v1/comments/:id
#   def update
#     unless @comment.user == current_user
#       return render json: { error: "Forbidden" }, status: :forbidden
#     end

#     if @comment.update(comment_params)
#       render json: @comment
#     else
#       render json: { errors: @comment.errors.full_messages }, status: :unprocessable_entity
#     end
#   end

#   # DELETE /api/v1/comments/:id
#   def destroy
#     unless @comment.user == current_user
#       return render json: { error: "Forbidden" }, status: :forbidden
#     end

#     @comment.destroy
#     head :no_content
#   end

#   private

#   def set_comment
#     @comment = Comment.find(params[:id])
#   rescue ActiveRecord::RecordNotFound
#     render json: { error: "Comment not found" }, status: :not_found
#   end

#   def comment_params
#     params.require(:comment).permit(:content, :movie_id)
#   end
# end
# COMMENTS_CTRL
#   echo "  comments_controller.rb created."
# fi

# # ─── 7. Database setup ───────────────────────────────────────────────────────
# step "Setting up the database"
# bundle exec rails db:create && echo "  Database created." || echo "  Database may already exist – continuing."

# echo ""
# echo "╔══════════════════════════════════════════════════════════╗"
# echo "║  ✓  Hypertube API bootstrap complete!                   ║"
# echo "║                                                          ║"
# echo "║  Next steps:                                             ║"
# echo "║    make up       – Start all services                   ║"
# echo "║    make migrate  – Run any pending migrations            ║"
# echo "║    make console  – Open the Rails console                ║"
# echo "║    make test     – Run the test suite                    ║"
# echo "║                                                          ║"
# echo "║  API docs available at: http://localhost:3000/api-docs   ║"
# echo "╚══════════════════════════════════════════════════════════╝"
# echo ""
