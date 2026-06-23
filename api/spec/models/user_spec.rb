require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  describe "validations" do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:username) }
    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to validate_presence_of(:last_name) }
    it { is_expected.to validate_uniqueness_of(:username).case_insensitive }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }

    it "rejects usernames with special characters" do
      user.username = "bad user!"
      expect(user).not_to be_valid
    end

    it "rejects short usernames" do
      user.username = "ab"
      expect(user).not_to be_valid
    end

    it "rejects passwords from the French dictionary blacklist" do
      user.password = "abaisse"
      user.password_confirmation = "abaisse"

      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("is too common")
    end

    it "matches blacklisted passwords case-insensitively" do
      user.password = "ABANDON"
      user.password_confirmation = "ABANDON"

      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("is too common")
    end

    it "allows passwords that only contain a blacklisted word" do
      user.password = "abandon123!"
      user.password_confirmation = "abandon123!"

      expect(user).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:comments).dependent(:destroy) }
    it { is_expected.to have_many(:watch_histories).dependent(:destroy) }
    it { is_expected.to have_many(:watched_movies).through(:watch_histories).source(:movie) }
  end

  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid:      "123456",
        info: {
          email:      "oauth@example.com",
          first_name: "Jane",
          last_name:  "Doe",
          nickname:   "janedoe"
        }
      )
    end

    it "creates a user from an oauth response" do
      expect { User.from_omniauth(auth) }.to change(User, :count).by(1)
    end

    it "returns the same user on subsequent calls" do
      user1 = User.from_omniauth(auth)
      user2 = User.from_omniauth(auth)
      expect(user1.id).to eq(user2.id)
    end

    it "derives the username from the email when no nickname is given" do
      auth_no_nick = OmniAuth::AuthHash.new(
        provider: "google_oauth2", uid: "777",
        info: { email: "ada@example.com", first_name: "Ada", last_name: "Lovelace" }
      )
      user = User.from_omniauth(auth_no_nick)
      expect(user.username).to eq("ada")
    end

    it "falls back to the username when the provider omits names" do
      auth_bare = OmniAuth::AuthHash.new(
        provider: "fortytwo", uid: "888",
        info: { email: "noname@example.com", nickname: "noname" }
      )
      user = User.from_omniauth(auth_bare)
      expect(user).to be_persisted
      expect(user.first_name).to eq("noname")
      expect(user.last_name).to eq("noname")
      expect(user.username).to eq("noname")
    end

    it "sanitizes a provider nickname that violates the username format" do
      auth_hyphen = OmniAuth::AuthHash.new(
        provider: "fortytwo", uid: "97835",
        info: { email: "arosado-@student.42.fr", first_name: "Andre",
                last_name: "Rosado", nickname: "arosado-" }
      )
      user = User.from_omniauth(auth_hyphen)
      expect(user).to be_persisted
      expect(user.username).to eq("arosado_")
    end

    it "appends a numeric suffix when the derived username is taken" do
      create(:user, username: "arosado_")
      auth_hyphen = OmniAuth::AuthHash.new(
        provider: "fortytwo", uid: "97835",
        info: { email: "arosado-@student.42.fr", first_name: "Andre",
                last_name: "Rosado", nickname: "arosado-" }
      )
      user = User.from_omniauth(auth_hyphen)
      expect(user).to be_persisted
      expect(user.username).to eq("arosado__1")
    end
  end
end
