class Api::V1::CommentsController < ApplicationController
  before_action :set_comment, only: %i[show update destroy]

  PER_PAGE = 20

  # GET /api/v1/comments                  latest comments site-wide
  # GET /api/v1/movies/:movie_id/comments comments for one movie
  #
  # Paginated newest-first. Params: page, per_page (1-100, default 20).
  def index
    scope = Comment.order(created_at: :desc)
    scope = scope.where(movie_id: params[:movie_id]) if params[:movie_id]

    total    = scope.count
    comments = scope.limit(per_page).offset((page - 1) * per_page)

    render json: {
      page:        page,
      per_page:    per_page,
      total:       total,
      total_pages: (total.to_f / per_page).ceil,
      comments:    comments.as_json(only: %i[id content created_at],
                                    include: { user: { only: %i[id username] } })
    }
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

  def page
    [ params.fetch(:page, 1).to_i, 1 ].max
  end

  # Clamp per_page to a sane range so a client can't request the whole table.
  def per_page
    params.fetch(:per_page, PER_PAGE).to_i.clamp(1, 100)
  end

  def set_comment
    @comment = Comment.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Comment not found" }, status: :not_found
  end

  def comment_params
    params.require(:comment).permit(:content, :movie_id)
  end
end
