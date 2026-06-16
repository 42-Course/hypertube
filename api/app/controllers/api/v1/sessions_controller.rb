class Api::V1::SessionsController < ApplicationController
  include FirstPartyTokens

  skip_before_action :doorkeeper_authorize!, only: %i[create]

  # POST /api/v1/session
  #
  # Exchange email (or username) + password for a first-party access token.
  def create
    user = authenticate_user

    unless user
      # Same message for unknown account and wrong password: no enumeration.
      return render json: { error: "Invalid credentials" }, status: :unauthorized
    end

    token = issue_access_token(user)
    render json: token_payload(token, user), status: :created
  end

  # DELETE /api/v1/session
  #
  # Logout: revoke the access token presented in the Authorization header.
  def destroy
    doorkeeper_token&.revoke
    head :no_content
  end

  private

  def authenticate_user
    login = login_param
    return if login.blank?

    user = User.find_for_database_authentication(email: login) ||
           User.find_by(username: login)
    user if user&.valid_password?(params[:password].to_s)
  end

  def login_param
    (params[:login] || params[:email] || params[:username]).to_s.strip.presence
  end

  def token_payload(token, user)
    {
      access_token: token.token,
      token_type:   "Bearer",
      expires_in:   token.expires_in,
      user: user.as_json(only: %i[id username email profile_picture_url])
    }
  end
end
