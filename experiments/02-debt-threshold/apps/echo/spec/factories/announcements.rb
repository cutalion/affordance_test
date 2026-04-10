FactoryBot.define do
  factory :announcement do
    client
    title { "Need a babysitter" }
    description { "Looking for an experienced babysitter for two kids" }
    location { "123 Main St" }
    scheduled_at { 3.days.from_now }
    duration_minutes { 180 }
    budget_cents { 500_000 }
    currency { "RUB" }

    trait :published do
      state { "published" }
      published_at { Time.current }
    end

    trait :closed do
      state { "closed" }
      published_at { 1.day.ago }
      closed_at { Time.current }
    end
  end
end
