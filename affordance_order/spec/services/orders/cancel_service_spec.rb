require "rails_helper"

RSpec.describe Orders::CancelService do
  let(:client) { create(:client) }
  let(:other_client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:order) { create(:order, client: client, provider: provider) }

  describe "#call" do
    it "cancels a pending order" do
      result = described_class.new(order: order, client: client, reason: "Changed my mind").call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("canceled")
    end

    it "cancels a confirmed order" do
      confirmed_order = create(:order, :confirmed, client: client, provider: provider)
      result = described_class.new(order: confirmed_order, client: client, reason: "Emergency").call
      expect(result[:success]).to be true
      expect(confirmed_order.reload.state).to eq("canceled")
    end

    context "when payment is held" do
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, order: order, card: card) }

      it "refunds the held payment" do
        described_class.new(order: order, client: client, reason: "Changed my mind").call
        expect(payment.reload.status).to eq("refunded")
      end
    end

    it "notifies the provider" do
      described_class.new(order: order, client: client, reason: "Changed my mind").call
      expect(read_notification_log).to include("event=order_canceled")
    end

    it "fails without a reason" do
      result = described_class.new(order: order, client: client, reason: "").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Cancel reason is required")
    end

    it "fails for wrong client" do
      result = described_class.new(order: order, client: other_client, reason: "Changed my mind").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your order")
    end

    it "fails for in_progress order" do
      in_progress_order = create(:order, :in_progress, client: client, provider: provider)
      result = described_class.new(order: in_progress_order, client: client, reason: "Changed my mind").call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot cancel order")
    end
  end
end
