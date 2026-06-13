# frozen_string_literal: true

# Customises Devise's transactional emails so links point at the React SPA
# (which talks to this API) rather than the Rails HTML routes.
class DeviseMailer < Devise::Mailer
  default template_path: "devise/mailer"

  def reset_password_instructions(record, token, opts = {})
    @frontend_reset_url =
      "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/reset-password?token=#{token}"
    super
  end
end
