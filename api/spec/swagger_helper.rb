require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.join("swagger").to_s

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Hypertube API",
        version: "v1",
        description: "RESTful API with OAuth2 authentication for the Hypertube video platform"
      },
      components: {
        securitySchemes: {
          oauth2: {
            type: :oauth2,
            flows: {
              password: {
                tokenUrl: "/oauth/token",
                scopes: {}
              }
            }
          }
        }
      },
      security: [ { oauth2: [] } ],
      # Both known deployments are baked into the generated swagger.yaml so the
      # same file works everywhere — Swagger UI shows a dropdown to switch.
      # Production is listed first so it is the default when served from
      # https://fractalia.art/api-docs.
      servers: [
        {
          url: "https://fractalia.art",
          description: "Production"
        },
        {
          url: "http://localhost:3000",
          description: "Development"
        }
      ]
    }
  }

  config.openapi_format = :yaml
end
