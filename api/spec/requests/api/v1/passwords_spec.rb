require "swagger_helper"

RSpec.describe "Password reset API", type: :request do
  let(:user) { create(:user, email: "forgetful@example.com") }

  before { ActionMailer::Base.deliveries.clear }

  path "/api/v1/password" do
    post "Request a password reset email" do
      tags     "Authentication"
      security []
      consumes "application/json"
      produces "application/json"
      description "Sends reset instructions to the email if it is registered. " \
                  "Always returns 200 so accounts cannot be enumerated."
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            required: %w[email],
            properties: { email: { type: :string, example: "forgetful@example.com" } }
          }
        }
      }

      response "200", "instructions sent for a known email" do
        before { user }
        let(:body) { { user: { email: user.email } } }
        run_test! do
          expect(ActionMailer::Base.deliveries.size).to eq(1)
          expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
        end
      end

      response "200", "same response for an unknown email (no enumeration)" do
        let(:body) { { user: { email: "nobody@example.com" } } }
        run_test! do
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end
    end

    patch "Set a new password using the reset token" do
      tags     "Authentication"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[user],
        properties: {
          user: {
            type: :object,
            required: %w[reset_password_token password],
            properties: {
              reset_password_token:  { type: :string },
              password:              { type: :string, example: "NewPass1!" },
              password_confirmation: { type: :string, example: "NewPass1!" }
            }
          }
        }
      }

      response "200", "password reset with a valid token" do
        let(:token) { user.send_reset_password_instructions }
        let(:body) do
          { user: { reset_password_token: token, password: "NewPass1!",
                    password_confirmation: "NewPass1!" } }
        end
        run_test! do
          expect(user.reload.valid_password?("NewPass1!")).to be(true)
        end
      end

      response "422", "invalid or expired token" do
        let(:body) do
          { user: { reset_password_token: "not-a-real-token", password: "NewPass1!",
                    password_confirmation: "NewPass1!" } }
        end
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data).to have_key("errors")
        end
      end

      response "422", "blacklisted password" do
        let(:token) { user.send_reset_password_instructions }
        let(:body) do
          { user: { reset_password_token: token, password: "abaisse",
                    password_confirmation: "abaisse" } }
        end
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["errors"]).to include("Password is too common")
          expect(user.reload.valid_password?("abaisse")).to be(false)
        end
      end
    end
  end
end
