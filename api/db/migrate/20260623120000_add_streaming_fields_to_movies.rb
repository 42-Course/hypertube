class AddStreamingFieldsToMovies < ActiveRecord::Migration[8.1]
  # media_id: the streaming service's deterministic id for this movie's torrent,
  # captured when a stream ticket is minted so the download-complete callback can
  # map a finished media back to its movie.
  # subtitle_languages: cached list of OpenSubtitles languages available for the
  # movie (keyed by imdb id), so the detail page can offer them without an
  # external call on every view.
  def change
    add_column :movies, :media_id, :string
    add_column :movies, :subtitle_languages, :jsonb, default: [], null: false
    add_index :movies, :media_id
  end
end
