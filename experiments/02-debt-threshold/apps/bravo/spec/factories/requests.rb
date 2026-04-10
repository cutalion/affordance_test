FactoryBot.define do
  factory :request do
    client
    provider
    scheduled_at { 3.days.from_now }
    duration_minutes { 120 }
    location { "123 Main St" }
    notes { "Please bring supplies" }

    trait :accepted do
      state { "accepted" }
      accepted_at { Time.current }
    end

    trait :declined do
      state { "declined" }
      decline_reason { "Not available" }
    end

    trait :expired do
      state { "expired" }
      expired_at { Time.current }
    end
  end
end
