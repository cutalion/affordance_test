FactoryBot.define do
  factory :review do
    association :request, :completed
    rating { 5 }
    body { "Excellent service!" }

    trait :by_client do
      association :author, factory: :client
    end

    trait :by_provider do
      association :author, factory: :provider
    end

    after(:build) do |review|
      if review.author_id.nil?
        review.author = review.request.client
      end
    end
  end
end
