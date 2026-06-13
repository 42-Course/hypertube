# frozen_string_literal: true

# The provider login is initiated by the SPA via a plain browser redirect
# (a GET to /users/auth/:provider). OmniAuth 2 only allows POST by default;
# we re-enable GET. This is safe because GET is a "safe" method (so the bundled
# omniauth-rails_csrf_protection still passes it) and the OAuth2 `state`
# parameter protects the callback against CSRF.
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true

# Send OmniAuth's own logging through the Rails logger.
OmniAuth.config.logger = Rails.logger

# On strategy errors, hand off to our callbacks controller's #failure action
# instead of raising, so the user is redirected back to the frontend.
OmniAuth.config.on_failure = proc do |env|
  Users::OmniauthCallbacksController.action(:failure).call(env)
end
