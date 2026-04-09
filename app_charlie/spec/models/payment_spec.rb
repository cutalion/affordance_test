require "rails_helper"

RSpec.describe Payment, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:request) }
    it { is_expected.to belong_to(:card).optional }
  end

  describe "validations" do
    subject { build(:payment) }

    it { is_expected.to validate_presence_of(:amount_cents) }
    it { is_expected.to validate_presence_of(:currency) }

    it "validates status inclusion" do
      payment = build(:payment, status: "invalid")
      expect(payment).not_to be_valid
      expect(payment.errors[:status]).to be_present

      %w[pending held charged refunded].each do |status|
        payment.status = status
        expect(payment).to be_valid
      end
    end

    it "validates amount_cents is >= 0" do
      payment = build(:payment, amount_cents: -1)
      expect(payment).not_to be_valid
    end
  end

  describe "#hold!" do
    let(:payment) { create(:payment) }

    it "updates status to held" do
      freeze_time do
        payment.hold!
        expect(payment.reload.status).to eq("held")
        expect(payment.held_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe "#charge!" do
    let(:payment) { create(:payment, :held) }

    it "updates status to charged" do
      freeze_time do
        payment.charge!
        expect(payment.reload.status).to eq("charged")
        expect(payment.charged_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe "#refund!" do
    let(:payment) { create(:payment, :charged) }

    it "updates status to refunded" do
      freeze_time do
        payment.refund!
        expect(payment.reload.status).to eq("refunded")
        expect(payment.refunded_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe ".by_status" do
    let!(:pending_payment) { create(:payment, status: "pending") }
    let!(:held_payment) { create(:payment, :held) }

    it "filters payments by status" do
      expect(Payment.by_status("pending")).to include(pending_payment)
      expect(Payment.by_status("pending")).not_to include(held_payment)
    end

    it "returns all when status is blank" do
      expect(Payment.by_status(nil).count).to eq(Payment.count)
    end
  end
end
