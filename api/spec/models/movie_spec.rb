require "rails_helper"

RSpec.describe Movie, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "associations" do
    it { is_expected.to have_many(:comments).dependent(:destroy) }
    it { is_expected.to have_many(:watch_histories).dependent(:destroy) }
  end

  describe "#magnet_uri" do
    it "builds a btih magnet from the stored info-hash (lower-cased)" do
      movie = build(:movie, magnet_hash: "ABCDEF0123456789ABCDEF0123456789ABCDEF01")
      expect(movie.magnet_uri).to eq("magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01")
    end

    it "returns nil when no torrent has been resolved" do
      expect(build(:movie, magnet_hash: nil).magnet_uri).to be_nil
    end
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

  describe ".upsert_from_source with duplicate natural keys" do
    it "does not claim a tmdb_id already owned by another movie" do
      canonical = create(:movie, tmdb_id: 50_275, imdb_id: nil, title: "Canonical")
      dup       = create(:movie, tmdb_id: nil, imdb_id: "tt2608732", title: "Older")

      result = MovieSources::Result.new(tmdb_id: 50_275, imdb_id: "tt2608732",
                                        title: "TPB AFK", summary: "Doc.")

      expect { Movie.upsert_from_source(result) }.not_to raise_error
      # Lands on the canonical tmdb row and leaves the duplicate's keys intact.
      expect(Movie.find_by(tmdb_id: 50_275).id).to eq(canonical.id)
      expect(canonical.reload.imdb_id).to be_nil
      expect(dup.reload.tmdb_id).to be_nil
    end
  end

  describe "#mark_watched_by" do
    let(:movie) { create(:movie) }
    let(:user)  { create(:user) }

    it "marks the movie as watched by the user" do
      movie.mark_watched_by(user)
      expect(movie.watched_by?(user)).to be true
    end

    it "is idempotent (no duplicate history rows)" do
      movie.mark_watched_by(user)
      expect { movie.mark_watched_by(user) }
        .not_to change { movie.watch_histories.where(user: user).count }.from(1)
    end

    it "bumps last_watched_at" do
      expect { movie.mark_watched_by(user) }
        .to change { movie.reload.last_watched_at }.from(nil)
    end
  end

  describe "#mark_unwatched_by" do
    let(:movie) { create(:movie) }
    let(:user)  { create(:user) }

    it "clears the user's watched mark" do
      movie.mark_watched_by(user)
      movie.mark_unwatched_by(user)
      expect(movie.watched_by?(user)).to be false
    end

    it "is idempotent when never watched" do
      expect { movie.mark_unwatched_by(user) }.not_to raise_error
      expect(movie.watched_by?(user)).to be false
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
