require "rails_helper"

RSpec.describe Card, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:client) }
  end

  describe "validations" do
    subject { build(:card) }

    it { is_expected.to validate_presence_of(:token) }
    it { is_expected.to validate_presence_of(:last_four) }
    it { is_expected.to validate_presence_of(:brand) }
    it { is_expected.to validate_presence_of(:exp_month) }
    it { is_expected.to validate_presence_of(:exp_year) }

    it "validates last_four length is exactly 4" do
      card = build(:card, last_four: "123")
      expect(card).not_to be_valid
      expect(card.errors[:last_four]).to be_present

      card.last_four = "12345"
      expect(card).not_to be_valid
    end

    it "validates brand inclusion" do
      card = build(:card, brand: "discover")
      expect(card).not_to be_valid
      expect(card.errors[:brand]).to be_present

      %w[visa mastercard amex mir].each do |brand|
        card.brand = brand
        expect(card).to be_valid
      end
    end

    it "validates exp_month is between 1 and 12" do
      card = build(:card, exp_month: 0)
      expect(card).not_to be_valid

      card.exp_month = 13
      expect(card).not_to be_valid

      card.exp_month = 6
      expect(card).to be_valid
    end

    it "validates exp_year is >= 2024" do
      card = build(:card, exp_year: 2023)
      expect(card).not_to be_valid

      card.exp_year = 2024
      expect(card).to be_valid
    end
  end

  describe "#make_default!" do
    let(:client) { create(:client) }
    let!(:card1) { create(:card, client: client, default: true) }
    let!(:card2) { create(:card, client: client, default: false) }

    it "sets the card as default" do
      card2.make_default!
      expect(card2.reload).to be_default
    end

    it "unsets other cards as default" do
      card2.make_default!
      expect(card1.reload).not_to be_default
    end
  end

  describe "ensure_single_default callback" do
    let(:client) { create(:client) }

    it "unsets other defaults when a new default is saved" do
      card1 = create(:card, client: client, default: true)
      card2 = create(:card, client: client, default: false)

      card2.update!(default: true)

      expect(card1.reload).not_to be_default
      expect(card2.reload).to be_default
    end
  end
end
