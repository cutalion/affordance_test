require "rails_helper"

RSpec.describe Review, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:order) }
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

    it "validates order must be completed" do
      order = create(:order) # pending state
      client = order.client
      review = build(:review, order: order, author: client)
      expect(review).not_to be_valid
      expect(review.errors[:order]).to be_present
    end

    it "is valid when order is completed" do
      review = build(:review)
      expect(review).to be_valid
    end

    describe "uniqueness per order and author" do
      let(:order) { create(:order, :completed) }
      let(:client) { order.client }

      it "prevents duplicate review from same author on same order" do
        create(:review, order: order, author: client)
        duplicate = build(:review, order: order, author: client)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:order_id]).to be_present
      end

      it "allows different authors to review the same order" do
        create(:review, order: order, author: client)
        provider = order.provider
        second_review = build(:review, order: order, author: provider)
        expect(second_review).to be_valid
      end
    end
  end
end
