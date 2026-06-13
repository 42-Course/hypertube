require "rails_helper"
require "omniauth/strategies/fortytwo"

RSpec.describe OmniAuth::Strategies::Fortytwo do
  subject(:strategy) { described_class.new(:app) }

  let(:raw_info) do
    {
      "id"          => 42,
      "email"       => "bocal@42.fr",
      "displayname" => "Bocal Staff",
      "first_name"  => "Bocal",
      "last_name"   => "Staff",
      "login"       => "bocal",
      "image"       => { "link" => "https://cdn.intra.42.fr/users/bocal.jpg" }
    }
  end

  describe "#raw_info" do
    it "fetches the profile from the /v2/me endpoint" do
      response     = instance_double("OAuth2::Response", parsed: raw_info)
      access_token = instance_double("OAuth2::AccessToken")
      allow(access_token).to receive(:get).with("/v2/me").and_return(response)
      allow(strategy).to receive(:access_token).and_return(access_token)

      expect(strategy.raw_info).to eq(raw_info)
    end
  end

  describe "mapped fields" do
    before { allow(strategy).to receive(:raw_info).and_return(raw_info) }

    it "maps the uid to the 42 id as a string" do
      expect(strategy.uid).to eq("42")
    end

    it "maps the info hash from the profile" do
      expect(strategy.info).to include(
        email:      "bocal@42.fr",
        name:       "Bocal Staff",
        first_name: "Bocal",
        last_name:  "Staff",
        nickname:   "bocal",
        image:      "https://cdn.intra.42.fr/users/bocal.jpg"
      )
    end

    it "exposes the raw payload under extra" do
      expect(strategy.extra).to eq(raw_info: raw_info)
    end
  end

  describe "#callback_url" do
    it "omits the query string so it matches the registered redirect_uri" do
      allow(strategy).to receive(:full_host).and_return("https://api.example.com")
      allow(strategy).to receive(:callback_path).and_return("/users/auth/fortytwo/callback")
      expect(strategy.callback_url).to eq("https://api.example.com/users/auth/fortytwo/callback")
    end
  end
end
