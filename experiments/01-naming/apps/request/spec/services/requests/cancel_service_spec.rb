require "rails_helper"

RSpec.describe Requests::CancelService do
  let(:client) { create(:client) }
  let(:other_client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:req) { create(:request, client: client, provider: provider) }

  describe "#call" do
    it "cancels a created request" do
      result = described_class.new(request: req, client: client, reason: "Changed my mind").call
      expect(result[:success]).to be true
      expect(req.reload.state).to eq("canceled")
    end

    it "cancels an accepted request" do
      accepted_request = create(:request, :accepted, client: client, provider: provider)
      result = described_class.new(request: accepted_request, client: client, reason: "Emergency").call
      expect(result[:success]).to be true
      expect(accepted_request.reload.state).to eq("canceled")
    end

    context "when payment is held" do
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, request: req, card: card) }

      it "refunds the held payment" do
        described_class.new(request: req, client: client, reason: "Changed my mind").call
        expect(payment.reload.status).to eq("refunded")
      end
    end

    it "notifies the provider" do
      described_class.new(request: req, client: client, reason: "Changed my mind").call
      expect(read_notification_log).to include("event=request_canceled")
    end

    it "fails without a reason" do
      result = described_class.new(request: req, client: client, reason: "").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Cancel reason is required")
    end

    it "fails for wrong client" do
      result = described_class.new(request: req, client: other_client, reason: "Changed my mind").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your request")
    end

    it "fails for started request" do
      started_request = create(:request, :started, client: client, provider: provider)
      result = described_class.new(request: started_request, client: client, reason: "Changed my mind").call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot cancel request")
    end
  end
end
