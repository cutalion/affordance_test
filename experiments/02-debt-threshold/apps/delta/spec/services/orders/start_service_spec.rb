require "rails_helper"

RSpec.describe Orders::StartService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:order) { create(:order, :confirmed, client: client, provider: provider) }

  describe "#call" do
    it "starts a confirmed order" do
      result = described_class.new(order: order, provider: provider).call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("in_progress")
    end

    it "notifies the client" do
      described_class.new(order: order, provider: provider).call
      expect(read_notification_log).to include("event=order_started")
    end

    it "fails for wrong provider" do
      result = described_class.new(order: order, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your order")
    end

    it "fails for pending order" do
      pending_order = create(:order, client: client, provider: provider)
      result = described_class.new(order: pending_order, provider: provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot start order")
    end
  end
end
