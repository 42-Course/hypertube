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