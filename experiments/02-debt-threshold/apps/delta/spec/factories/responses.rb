FactoryBot.define do
  factory :response do
    announcement { association :announcement, :published }
    provider
    message { "I am available and experienced" }
    proposed_amount_cents { 450_000 }

    trait :selected do
      state { "selected" }
    end

    trait :rejected do
      state { "rejected" }
    end
  end
end
