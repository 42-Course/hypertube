# frozen_string_literal: true

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    # OmniAuth strategy for 42's OAuth2 provider (https://api.intra.42.fr).
    # Built on omniauth-oauth2 so no extra gem is required.
    #
    # The provider symbol is :fortytwo, which OmniAuth camelizes to
    # `OmniAuth::Strategies::Fortytwo` so the class name must stay "Fortytwo".
    class Fortytwo < OmniAuth::Strategies::OAuth2
      option :name, "fortytwo"

      option :client_options, {
        site:          "https://api.intra.42.fr",
        authorize_url: "/oauth/authorize",
        token_url:     "/oauth/token"
      }

      option :scope, "public"

      uid { raw_info["id"].to_s }

      info do
        {
          email:      raw_info["email"],
          name:       raw_info["displayname"],
          first_name: raw_info["first_name"],
          last_name:  raw_info["last_name"],
          nickname:   raw_info["login"],
          image:      raw_info.dig("image", "link")
        }
      end

      extra do
        { raw_info: raw_info }
      end

      def raw_info
        @raw_info ||= access_token.get("/v2/me").parsed
      end

      # 42 rejects requests where the redirect_uri carries a query string,
      # so strip it to match exactly what was registered.
      def callback_url
        full_host + callback_path
      end
    end
  end
end
