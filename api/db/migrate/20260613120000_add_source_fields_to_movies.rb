class AddSourceFieldsToMovies < ActiveRecord::Migration[8.1]
  # Movies are aggregated from external sources (YTS, TMDb). We key each record
  # on whichever natural identifier the source provides so the same film is never
  # stored twice, while still exposing a stable integer `id` to API clients.
  def change
    add_column :movies, :tmdb_id,    :integer
    add_column :movies, :popularity, :decimal, precision: 10, scale: 3

    # Partial unique indexes: a natural key is unique only when present.
    add_index :movies, :imdb_id, unique: true, where: "imdb_id IS NOT NULL"
    add_index :movies, :tmdb_id, unique: true, where: "tmdb_id IS NOT NULL"
  end
end
