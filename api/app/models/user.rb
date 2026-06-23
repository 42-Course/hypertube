class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :omniauthable, omniauth_providers: %i[google_oauth2 fortytwo github microsoft]

  has_many :comments, dependent: :destroy
  has_many :watch_histories, dependent: :destroy
  has_many :watched_movies, through: :watch_histories, source: :movie

  # Uploaded profile image. When attached it takes precedence over the
  # profile_picture_url string column (which still holds external OAuth avatars).
  has_one_attached :avatar

  validates :username,   presence: true, uniqueness: { case_sensitive: false },
                         format: { with: /\A[a-zA-Z0-9_]+\z/ }, length: { minimum: 3 }
  validates :first_name, presence: true
  validates :last_name,  presence: true
  validates :password,   password_blacklist: true, if: -> { password.present? }

  # Prefer the uploaded avatar (served via Active Storage) over the external
  # OAuth image stored in the string column. Returns an absolute URL so API
  # clients (frontend) can use it directly.
  def profile_picture_url
    return self[:profile_picture_url] unless avatar.attached?

    api_base_url + Rails.application.routes.url_helpers.rails_blob_path(avatar, only_path: true)
  end

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email               = auth.info.email
      user.password            = Devise.friendly_token[0, 20]
      user.username            = unique_username_from(auth)
      user.first_name          = auth.info.first_name.presence || user.username
      user.last_name           = auth.info.last_name.presence  || user.username
      user.profile_picture_url = auth.info.image.presence
    end
  end

  def self.unique_username_from(auth)
    base = (auth.info.nickname.presence || auth.info.email.to_s.split("@").first.to_s)
             .gsub(/[^a-zA-Z0-9_]/, "_")
    base = "user" if base.length < 3

    candidate = base
    counter = 0
    while exists?([ "LOWER(username) = LOWER(?)", candidate ])
      counter += 1
      candidate = "#{base}_#{counter}"
    end
    candidate
  end

  private

  # Base for absolute Active Storage URLs. In production this is the public API
  # host; falls back to localhost in development/test.
  def api_base_url
    ENV.fetch("API_URL", "http://localhost:3000").chomp("/")
  end
end
