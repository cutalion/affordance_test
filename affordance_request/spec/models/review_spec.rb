require "rails_helper"

RSpec.describe Review, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:request) }
    it { is_expected.to belong_to(:author).without_validating_presence }
  end

  describe "validations" do
    subject { build(:review) }

    it { is_expected.to validate_presence_of(:rating) }

    it "validates rating is between 1 and 5" do
      review = build(:review, rating: 0)
      expect(review).not_to be_valid

      review.rating = 6
      expect(review).not_to be_valid

      (1..5).each do |r|
        review.rating = r
        expect(review).to be_valid
      end
    end

    it "has an inclusion validation on author_type for Client and Provider" do
      validator = Review.validators_on(:author_type).find do |v|
        v.is_a?(ActiveModel::Validations::InclusionValidator)
      end
      expect(validator).to be_present
      expect(validator.options[:in]).to contain_exactly("Client", "Provider")
    end

    it "accepts valid author_types" do
      client_review = build(:review, author: build(:client))
      expect(client_review).to be_valid
    end

    it "validates request must be fulfilled" do
      req = create(:request) # created state
      client = req.client
      review = build(:review, request: req, author: client)
      expect(review).not_to be_valid
      expect(review.errors[:request]).to be_present
    end

    it "is valid when request is fulfilled" do
      review = build(:review)
      expect(review).to be_valid
    end

    describe "uniqueness per request and author" do
      let(:req) { create(:request, :fulfilled) }
      let(:client) { req.client }

      it "prevents duplicate review from same author on same request" do
        create(:review, request: req, author: client)
        duplicate = build(:review, request: req, author: client)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:request_id]).to be_present
      end

      it "allows different authors to review the same request" do
        create(:review, request: req, author: client)
        provider = req.provider
        second_review = build(:review, request: req, author: provider)
        expect(second_review).to be_valid
      end
    end
  end
end
