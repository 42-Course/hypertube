# frozen_string_literal: true

class AddDeviseToUsers < ActiveRecord::Migration[8.1]
  def self.up
    create_table :users do |t|
      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer  :sign_in_count,      default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Profile
      t.string :username,             null: false, default: ""
      t.string :first_name,           null: false, default: ""
      t.string :last_name,            null: false, default: ""
      t.string :profile_picture_url
      t.string :preferred_language,   null: false, default: "en"

      ## OmniAuth (42 Intra + Google)
      t.string :provider
      t.string :uid

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :username,             unique: true
    add_index :users, %i[provider uid],      unique: true, name: "index_users_on_provider_and_uid"
  end

  def self.down
    drop_table :users
  end
end
