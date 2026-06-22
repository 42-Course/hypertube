# frozen_string_literal: true

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    # OmniAuth strategy for GitHub's OAuth2 provider (https://github.com).
    # Built on omniauth-oauth2 so no extra gem is required.
    #
    # The provider symbol is :github, which OmniAuth camelizes to
    # `OmniAuth::Strategies::Github` so the class name must stay "Github".
    class Github < OmniAuth::Strategies::OAuth2
      option :name, "github"

      option :client_options, {
        site:          "https://api.github.com",
        authorize_url: "https://github.com/login/oauth/authorize",
        token_url:     "https://github.com/login/oauth/access_token"
      }

      # `user:email` is needed so we can read the (possibly private) primary
      # email via the /user/emails endpoint.
      option :scope, "read:user user:email"

      uid { raw_info["id"].to_s }

      info do
        {
          email:      primary_email,
          name:       raw_info["name"],
          first_name: raw_info["name"].to_s.split(" ").first,
          last_name:  raw_info["name"].to_s.split(" ")[1..]&.join(" "),
          nickname:   raw_info["login"],
          image:      raw_info["avatar_url"]
        }
      end

      extra do
        { raw_info: raw_info }
      end

      def raw_info
        @raw_info ||= access_token.get("/user").parsed
      end

      # GitHub omits the email from /user when the user keeps it private, so we
      # fall back to the dedicated emails endpoint and pick the primary verified
      # address.
      def primary_email
        return raw_info["email"] if raw_info["email"].present?

        emails.find { |e| e["primary"] && e["verified"] }&.fetch("email", nil) ||
          emails.first&.fetch("email", nil)
      end

      def emails
        @emails ||= access_token.get("/user/emails").parsed
      rescue StandardError
        []
      end

      # Match exactly what was registered as the callback by stripping any
      # query string from the redirect_uri.
      def callback_url
        full_host + callback_path
      end
    end
  end
end
