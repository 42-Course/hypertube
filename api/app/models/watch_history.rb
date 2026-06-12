class WatchHistory < ApplicationRecord
  belongs_to :user
  belongs_to :movie

  after_create :touch_movie_last_watched

  private

  def touch_movie_last_watched
    movie.update_column(:last_watched_at, Time.current)
  end
end
