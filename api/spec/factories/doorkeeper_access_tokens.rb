FactoryBot.define do
  factory :doorkeeper_access_token, class: "Doorkeeper::AccessToken" do
    association :application, factory: :doorkeeper_application
    resource_owner_id { create(:user).id }
    scopes            { "" }
    expires_in        { 2.hours }
    use_refresh_token { false }
  end
end
