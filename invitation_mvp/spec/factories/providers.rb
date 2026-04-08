FactoryBot.define do
  factory :provider do
    sequence(:email) { |n| "provider#{n}@example.com" }
    name { "Test Provider" }
    phone { "+79007654321" }
    specialization { "cleaning" }
    active { true }
    rating { 4.5 }
    notification_preferences { { "push" => true, "sms" => true, "email" => true } }
  end
end
