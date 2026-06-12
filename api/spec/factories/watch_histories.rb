FactoryBot.define do
  factory :watch_history do
    user { nil }
    movie { nil }
    completed { false }
  end
end
