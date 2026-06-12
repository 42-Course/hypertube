require "rails_helper"

RSpec.describe Movie, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "associations" do
    it { is_expected.to have_many(:comments).dependent(:destroy) }
    it { is_expected.to have_many(:watch_histories).dependent(:destroy) }
  end

  describe "#watched_by?" do
    let(:movie) { create(:movie) }
    let(:user)  { create(:user) }

    it "returns false when the user has not watched the movie" do
      expect(movie.watched_by?(user)).to be false
    end

    it "returns true after the user watches the movie" do
      create(:watch_history, user: user, movie: movie)
      expect(movie.watched_by?(user)).to be true
    end
  end

  describe ".stale" do
    it "includes movies unwatched for over a month" do
      stale = create(:movie, last_watched_at: 2.months.ago, file_path: "/tmp/old.mp4")
      expect(Movie.stale).to include(stale)
    end

    it "excludes recently watched movies" do
      recent = create(:movie, last_watched_at: 1.day.ago, file_path: "/tmp/new.mp4")
      expect(Movie.stale).not_to include(recent)
    end
  end
end
