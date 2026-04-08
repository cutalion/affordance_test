require "rails_helper"

RSpec.describe Orders::ConfirmService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:order) { create(:order, client: client, provider: provider) }

  describe "#call" do
    it "confirms a pending order" do
      result = described_class.new(order: order, provider: provider).call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("confirmed")
    end

    it "notifies the client" do
      described_class.new(order: order, provider: provider).call
      expect(read_notification_log).to include("event=order_confirmed")
    end

    it "fails for wrong provider" do
      result = described_class.new(order: order, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your order")
    end

    it "fails for non-pending order" do
      order.update!(state: "confirmed")
      result = described_class.new(order: order, provider: provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot confirm order")
    end
  end
end
