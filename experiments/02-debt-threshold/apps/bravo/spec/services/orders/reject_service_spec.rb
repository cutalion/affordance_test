require "rails_helper"

RSpec.describe Orders::RejectService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }

  describe "#call" do
    it "rejects a confirmed order" do
      confirmed_order = create(:order, :confirmed, client: client, provider: provider)
      result = described_class.new(order: confirmed_order, provider: provider, reason: "Not available").call
      expect(result[:success]).to be true
      expect(confirmed_order.reload.state).to eq("rejected")
    end

    it "rejects an in_progress order" do
      in_progress_order = create(:order, :in_progress, client: client, provider: provider)
      result = described_class.new(order: in_progress_order, provider: provider, reason: "Emergency").call
      expect(result[:success]).to be true
      expect(in_progress_order.reload.state).to eq("rejected")
    end

    context "when payment is held" do
      let(:order) { create(:order, :confirmed, client: client, provider: provider) }
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, order: order, card: card) }

      it "refunds the held payment" do
        described_class.new(order: order, provider: provider, reason: "Not available").call
        expect(payment.reload.status).to eq("refunded")
      end
    end

    it "notifies the client" do
      confirmed_order = create(:order, :confirmed, client: client, provider: provider)
      described_class.new(order: confirmed_order, provider: provider, reason: "Not available").call
      expect(read_notification_log).to include("event=order_rejected")
    end

    it "fails without a reason" do
      confirmed_order = create(:order, :confirmed, client: client, provider: provider)
      result = described_class.new(order: confirmed_order, provider: provider, reason: "").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Reject reason is required")
    end

    it "fails for pending order" do
      pending_order = create(:order, client: client, provider: provider)
      result = described_class.new(order: pending_order, provider: provider, reason: "Not available").call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot reject order")
    end
  end
end
