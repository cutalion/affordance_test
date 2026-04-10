require "rails_helper"

RSpec.describe Orders::CompleteService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:order) { create(:order, :in_progress, client: client, provider: provider) }

  describe "#call" do
    it "completes an in_progress order" do
      result = described_class.new(order: order, provider: provider).call
      expect(result[:success]).to be true
      expect(order.reload.state).to eq("completed")
    end

    context "when payment is held" do
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, order: order, card: card) }

      it "charges the held payment" do
        described_class.new(order: order, provider: provider).call
        expect(payment.reload.status).to eq("charged")
      end
    end

    it "notifies both client and provider" do
      described_class.new(order: order, provider: provider).call
      log = read_notification_log
      expect(log).to include("client_#{order.client_id}")
      expect(log).to include("provider_#{order.provider_id}")
      expect(log).to include("event=order_completed")
    end

    it "fails for wrong provider" do
      result = described_class.new(order: order, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your order")
    end
  end
end
