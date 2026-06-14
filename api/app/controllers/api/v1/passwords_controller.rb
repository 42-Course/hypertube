class Api::V1::PasswordsController < ApplicationController
  # Public: a user who forgot their password obviously has no token.
  skip_before_action :doorkeeper_authorize!

  # POST /api/v1/password request a reset email.
  #
  # Always responds 200 with the same message, whether or not the email is
  # registered, so the endpoint cannot be used to enumerate accounts.
  def create
    User.send_reset_password_instructions(email: params.dig(:user, :email))

    render json: {
      message: "If an account with that email exists, password reset " \
               "instructions have been sent."
    }
  end

  # PATCH/PUT /api/v1/password set a new password using the emailed token.
  def update
    user = User.reset_password_by_token(
      reset_password_token:  params.dig(:user, :reset_password_token),
      password:              params.dig(:user, :password),
      password_confirmation: params.dig(:user, :password_confirmation)
    )

    if user.errors.empty?
      render json: { message: "Your password has been reset. You can now log in." }
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
