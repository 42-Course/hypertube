FactoryBot.define do
  factory :movie do
    sequence(:title) { |n| "Movie #{n}" }
    imdb_id          { "tt#{Faker::Number.number(digits: 7)}" }
    year             { Faker::Number.between(from: 1970, to: Date.today.year) }
    rating           { Faker::Number.decimal(l_digits: 1, r_digits: 1) }
    duration         { Faker::Number.between(from: 60, to: 180) }
    cover_url        { Faker::Internet.url }
    genres           { "Action" }
    summary          { Faker::Lorem.paragraph }
  end
end
