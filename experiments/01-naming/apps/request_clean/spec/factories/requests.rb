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

    trait :confirmed do
      state { "confirmed" }
    end

    trait :in_progress do
      state { "in_progress" }
      started_at { Time.current }
    end

    trait :completed do
      state { "completed" }
      started_at { 2.hours.ago }
      completed_at { Time.current }
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
      after(:create) do |request|
        create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
      end
    end

    trait :with_card do
      after(:create) do |request|
        create(:card, client: request.client, default: true)
      end
    end

    trait :scheduled_tomorrow do
      scheduled_at { 1.day.from_now }
    end
  end
end
