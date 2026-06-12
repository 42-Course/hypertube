class CreateMovies < ActiveRecord::Migration[8.1]
  def change
    create_table :movies do |t|
      t.string :imdb_id
      t.string :title
      t.integer :year
      t.decimal :rating
      t.integer :duration
      t.string :cover_url
      t.string :genres
      t.text :summary
      t.string :magnet_hash
      t.string :file_path
      t.datetime :last_watched_at

      t.timestamps
    end
  end
end
