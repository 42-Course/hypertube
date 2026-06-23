require "rails_helper"
require "omniauth/strategies/microsoft"

RSpec.describe OmniAuth::Strategies::Microsoft do
  subject(:strategy) { described_class.new(:app) }

  let(:raw_info) do
    {
      "id"          => "ms-1",
      "mail"        => "milo@example.com",
      "displayName" => "Milo Soft",
      "givenName"   => "Milo",
      "surname"     => "Soft"
    }
  end

  describe "#raw_info" do
    it "fetches the profile from the Graph /v1.0/me endpoint" do
      response     = instance_double("OAuth2::Response", parsed: raw_info)
      access_token = instance_double("OAuth2::AccessToken")
      allow(access_token).to receive(:get).with("/v1.0/me").and_return(response)
      allow(strategy).to receive(:access_token).and_return(access_token)

      expect(strategy.raw_info).to eq(raw_info)
    end
  end

  describe "mapped fields" do
    before { allow(strategy).to receive(:raw_info).and_return(raw_info) }

    it "maps the uid to the Microsoft id as a string" do
      expect(strategy.uid).to eq("ms-1")
    end

    it "maps the info hash from the profile" do
      expect(strategy.info).to include(
        email:      "milo@example.com",
        name:       "Milo Soft",
        first_name: "Milo",
        last_name:  "Soft",
        nickname:   "milo"
      )
    end

    it "falls back to userPrincipalName when mail is absent (personal accounts)" do
      allow(strategy).to receive(:raw_info).and_return(
        raw_info.except("mail").merge("userPrincipalName" => "milo@outlook.com")
      )
      expect(strategy.info[:email]).to eq("milo@outlook.com")
    end

    it "exposes the raw payload under extra" do
      expect(strategy.extra).to eq(raw_info: raw_info)
    end
  end

  describe "#callback_url" do
    it "omits the query string so it matches the registered redirect_uri" do
      allow(strategy).to receive(:full_host).and_return("https://api.example.com")
      allow(strategy).to receive(:callback_path).and_return("/users/auth/microsoft/callback")
      expect(strategy.callback_url).to eq("https://api.example.com/users/auth/microsoft/callback")
    end
  end
end
