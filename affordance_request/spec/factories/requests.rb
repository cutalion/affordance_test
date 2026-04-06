FactoryBot.define do
  factory :request do
    client
    provider
    scheduled_at { 3.days.from_now }
    duration_minutes { 120 }
    location { "123 Main St" }
    notes { "Please bring supplies" }
    amount_cents { 350_000 }
    currency { "RUB" }

    trait :created_accepted do
      state { "created_accepted" }
    end

    trait :accepted do
      state { "accepted" }
    end

    trait :started do
      state { "started" }
      started_at { Time.current }
    end

    trait :fulfilled do
      state { "fulfilled" }
      started_at { 2.hours.ago }
      completed_at { Time.current }
    end

    trait :declined do
      state { "declined" }
    end

    trait :missed do
      state { "missed" }
    end

    trait :canceled do
      state { "canceled" }
      cancel_reason { "Schedule changed" }
    end

    trait :rejected do
      state { "rejected" }
      reject_reason { "Cannot make it" }
    end

    trait :with_payment do
      after(:create) do |req|
        create(:payment, request: req, amount_cents: req.amount_cents, currency: req.currency)
      end
    end

    trait :with_card do
      after(:create) do |req|
        create(:card, client: req.client, default: true)
      end
    end

    trait :scheduled_tomorrow do
      scheduled_at { 1.day.from_now }
    end
  end
end
