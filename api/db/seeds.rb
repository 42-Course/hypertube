# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Creates:
#   * one demo user (username/password login)
#   * two Doorkeeper OAuth applications: one for the Swagger UI, one for the frontend SPA
#
# Everything is idempotent (find_or_create_by) and the relevant credentials are
# printed to STDOUT so they can be copied into the Swagger "Authorize" dialog or
# the frontend .env.

def banner(title)
  puts "\n\e[1m#{title}\e[0m"
  puts "-" * title.length
end

# ── Demo user ─────────────────────────────────────────────────────────────────
demo_password = ENV.fetch("SEED_USER_PASSWORD", "Password1!")

user = User.find_or_initialize_by(email: "demo@hypertube.local")
user.assign_attributes(
  username:           "demo",
  first_name:         "Demo",
  last_name:          "User",
  preferred_language: "en",
  password:           demo_password,
  password_confirmation: demo_password
)
user.save!

banner("Demo user")
puts "  email:     #{user.email}"
puts "  username:  #{user.username}"
puts "  password:  #{demo_password}"

# ── Doorkeeper OAuth applications ───────────────────────────────────────────────
# Confidential (server-side) clients use the Resource Owner Password grant.
def upsert_application(name)
  app = Doorkeeper::Application.find_or_create_by!(name: name) do |a|
    a.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
    a.confidential = true
    a.scopes       = ""
  end
  app
end

swagger_app  = upsert_application("swagger ui")
frontend_app = upsert_application("frontend")

# Machine-to-machine identity for the streaming service. It uses the
# client_credentials grant (see config/initializers/doorkeeper.rb) to call
# privileged internal API endpoints (e.g. recording watch history) on its own
# behalf. Viewer authorization itself rides on signed stream tickets, not on
# this client (see StreamTicket).
streaming_app = upsert_application("streaming-service")

[ [ "Swagger UI app", swagger_app ], [ "Frontend app", frontend_app ],
  [ "Streaming service app", streaming_app ] ].each do |label, app|
  banner(label)
  puts "  name:          #{app.name}"
  puts "  client_id:     #{app.uid}"
  puts "  client_secret: #{app.secret}"
end

banner("Done")
puts "  Use a client_id/client_secret above plus the demo user's"
puts "  username + password to obtain a token via POST /oauth/token."
puts
