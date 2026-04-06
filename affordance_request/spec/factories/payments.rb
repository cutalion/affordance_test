FactoryBot.define do
  factory :payment do
    request
    amount_cents { 350_000 }
    currency { "RUB" }
    fee_cents { 35_000 }
    status { "pending" }

    trait :held do
      status { "held" }
      held_at { Time.current }
      card
    end

    trait :charged do
      status { "charged" }
      held_at { 1.hour.ago }
      charged_at { Time.current }
      card
    end

    trait :refunded do
      status { "refunded" }
      held_at { 2.hours.ago }
      charged_at { 1.hour.ago }
      refunded_at { Time.current }
      card
    end
  end
end
