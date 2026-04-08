FactoryBot.define do
  factory :client do
    sequence(:email) { |n| "client#{n}@example.com" }
    name { "Test Client" }
    phone { "+79001234567" }
    notification_preferences { { "push" => true, "sms" => true, "email" => true } }
  end
end
