class Movie < ApplicationRecord
  has_many :comments, dependent: :destroy
  has_many :watch_histories, dependent: :destroy

  validates :title, presence: true

  scope :stale, -> { where("last_watched_at < ?", 1.month.ago).where.not(file_path: nil) }

  def watched_by?(user)
    watch_histories.exists?(user: user)
  end
end
