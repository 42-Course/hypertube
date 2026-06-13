class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :omniauthable, omniauth_providers: %i[google_oauth2 fortytwo]

  has_many :comments, dependent: :destroy
  has_many :watch_histories, dependent: :destroy
  has_many :watched_movies, through: :watch_histories, source: :movie

  validates :username,   presence: true, uniqueness: { case_sensitive: false },
                         format: { with: /\A[a-zA-Z0-9_]+\z/ }, length: { minimum: 3 }
  validates :first_name, presence: true
  validates :last_name,  presence: true

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email      = auth.info.email
      user.password   = Devise.friendly_token[0, 20]
      user.first_name = auth.info.first_name.presence || ""
      user.last_name  = auth.info.last_name.presence  || ""
      user.username   = auth.info.nickname.presence   || auth.info.email.to_s.split("@").first
    end
  end
end
