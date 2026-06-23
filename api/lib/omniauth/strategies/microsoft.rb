# frozen_string_literal: true

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    # OmniAuth strategy for Microsoft's identity platform (v2.0) backed by
    # Microsoft Graph. Built on omniauth-oauth2 so no extra gem is required.
    #
    # The provider symbol is :microsoft, which OmniAuth camelizes to
    # `OmniAuth::Strategies::Microsoft` so the class name must stay "Microsoft".
    #
    # Uses the "common" tenant so both work/school (Azure AD) and personal
    # (Outlook/Live) accounts can sign in.
    class Microsoft < OmniAuth::Strategies::OAuth2
      option :name, "microsoft"

      option :client_options, {
        site:          "https://graph.microsoft.com",
        authorize_url: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        token_url:     "https://login.microsoftonline.com/common/oauth2/v2.0/token"
      }

      option :authorize_params, { response_mode: "query" }

      option :scope, "openid email profile User.Read"

      uid { raw_info["id"].to_s }

      info do
        {
          # Work/school accounts expose `mail`; personal accounts only have
          # `userPrincipalName`, which is the email for those.
          email:      raw_info["mail"] || raw_info["userPrincipalName"],
          name:       raw_info["displayName"],
          first_name: raw_info["givenName"],
          last_name:  raw_info["surname"],
          nickname:   (raw_info["mail"] || raw_info["userPrincipalName"]).to_s.split("@").first
        }
      end

      extra do
        { raw_info: raw_info }
      end

      def raw_info
        @raw_info ||= access_token.get("/v1.0/me").parsed
      end

      # Microsoft requires the redirect_uri to match the registered value
      # exactly, so strip any query string.
      def callback_url
        full_host + callback_path
      end
    end
  end
end
