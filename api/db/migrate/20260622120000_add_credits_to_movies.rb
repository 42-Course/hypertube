class AddCreditsToMovies < ActiveRecord::Migration[8.1]
  # Cast + crew for the detail page, resolved lazily from TMDb (rich: names,
  # characters, profile photos, director/producer) with an OMDb/IMDb fallback.
  # Stored as one jsonb blob so the shape can vary by source without new columns.
  def change
    add_column :movies, :credits, :jsonb, default: {}, null: false
  end
end
