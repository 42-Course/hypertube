require "rails_helper"
require "omniauth/strategies/github"

RSpec.describe OmniAuth::Strategies::Github do
  subject(:strategy) { described_class.new(:app) }

  let(:raw_info) do
    {
      "id"         => 1,
      "email"      => "octo@example.com",
      "name"       => "Octo Cat",
      "login"      => "octocat",
      "avatar_url" => "https://avatars.githubusercontent.com/u/1"
    }
  end

  describe "#raw_info" do
    it "fetches the profile from the /user endpoint" do
      response     = instance_double("OAuth2::Response", parsed: raw_info)
      access_token = instance_double("OAuth2::AccessToken")
      allow(access_token).to receive(:get).with("/user").and_return(response)
      allow(strategy).to receive(:access_token).and_return(access_token)

      expect(strategy.raw_info).to eq(raw_info)
    end
  end

  describe "mapped fields" do
    before { allow(strategy).to receive(:raw_info).and_return(raw_info) }

    it "maps the uid to the GitHub id as a string" do
      expect(strategy.uid).to eq("1")
    end

    it "maps the info hash from the profile" do
      expect(strategy.info).to include(
        email:      "octo@example.com",
        name:       "Octo Cat",
        first_name: "Octo",
        last_name:  "Cat",
        nickname:   "octocat",
        image:      "https://avatars.githubusercontent.com/u/1"
      )
    end

    it "exposes the raw payload under extra" do
      expect(strategy.extra).to eq(raw_info: raw_info)
    end
  end

  describe "#primary_email" do
    it "falls back to the /user/emails endpoint when the profile email is private" do
      allow(strategy).to receive(:raw_info).and_return(raw_info.merge("email" => nil))
      emails = [
        { "email" => "secondary@example.com", "primary" => false, "verified" => true },
        { "email" => "primary@example.com",   "primary" => true,  "verified" => true }
      ]
      response     = instance_double("OAuth2::Response", parsed: emails)
      access_token = instance_double("OAuth2::AccessToken")
      allow(access_token).to receive(:get).with("/user/emails").and_return(response)
      allow(strategy).to receive(:access_token).and_return(access_token)

      expect(strategy.primary_email).to eq("primary@example.com")
    end
  end

  describe "#callback_url" do
    it "omits the query string so it matches the registered redirect_uri" do
      allow(strategy).to receive(:full_host).and_return("https://api.example.com")
      allow(strategy).to receive(:callback_path).and_return("/users/auth/github/callback")
      expect(strategy.callback_url).to eq("https://api.example.com/users/auth/github/callback")
    end
  end
end
