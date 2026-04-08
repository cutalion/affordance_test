FactoryBot.define do
  factory :card do
    client
    sequence(:token) { |n| "tok_#{SecureRandom.hex(12)}_#{n}" }
    last_four { "4242" }
    brand { "visa" }
    exp_month { 12 }
    exp_year { 2028 }
    default { false }

    trait :default do
      default { true }
    end
  end
end
