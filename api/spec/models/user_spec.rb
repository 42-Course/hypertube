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

    it "falls back to blank names when the provider omits them" do
      auth_bare = OmniAuth::AuthHash.new(
        provider: "fortytwo", uid: "888",
        info: { email: "noname@example.com", nickname: "noname" }
      )
      user = User.from_omniauth(auth_bare)
      expect(user.first_name).to eq("")
      expect(user.last_name).to eq("")
      expect(user.username).to eq("noname")
    end
  end
end
