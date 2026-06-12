class CreateWatchHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :watch_histories do |t|
      t.references :user, null: false, foreign_key: true
      t.references :movie, null: false, foreign_key: true
      t.boolean :completed

      t.timestamps
    end
  end
end
