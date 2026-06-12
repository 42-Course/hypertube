FactoryBot.define do
  factory :doorkeeper_application, class: "Doorkeeper::Application" do
    name         { "Test Application" }
    redirect_uri { "urn:ietf:wg:oauth:2.0:oob" }
    scopes       { "" }
    confidential { true }
  end
end
