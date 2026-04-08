require "rails_helper"

RSpec.describe Requests::CancelService do
  let(:client) { create(:client) }
  let(:other_client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:request) { create(:request, client: client, provider: provider) }

  describe "#call" do
    it "cancels a pending request" do
      result = described_class.new(request: request, client: client, reason: "Changed my mind").call
      expect(result[:success]).to be true
      expect(request.reload.state).to eq("canceled")
    end

    it "cancels an accepted request" do
      accepted_request = create(:request, :accepted, client: client, provider: provider)
      result = described_class.new(request: accepted_request, client: client, reason: "Emergency").call
      expect(result[:success]).to be true
      expect(accepted_request.reload.state).to eq("canceled")
    end

    context "when payment is held" do
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, request: request, card: card) }

      it "refunds the held payment" do
        described_class.new(request: request, client: client, reason: "Changed my mind").call
        expect(payment.reload.status).to eq("refunded")
      end
    end

    it "notifies the provider" do
      described_class.new(request: request, client: client, reason: "Changed my mind").call
      expect(read_notification_log).to include("event=request_canceled")
    end

    it "fails without a reason" do
      result = described_class.new(request: request, client: client, reason: "").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Cancel reason is required")
    end

    it "fails for wrong client" do
      result = described_class.new(request: request, client: other_client, reason: "Changed my mind").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your request")
    end

    it "fails for in_progress request" do
      in_progress_request = create(:request, :in_progress, client: client, provider: provider)
      result = described_class.new(request: in_progress_request, client: client, reason: "Changed my mind").call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot cancel request")
    end
  end
end
