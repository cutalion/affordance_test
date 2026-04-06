require "rails_helper"

RSpec.describe Requests::RejectService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }

  describe "#call" do
    it "rejects an accepted request" do
      accepted_request = create(:request, :accepted, client: client, provider: provider)
      result = described_class.new(request: accepted_request, provider: provider, reason: "Not available").call
      expect(result[:success]).to be true
      expect(accepted_request.reload.state).to eq("rejected")
    end

    it "rejects a started request" do
      started_request = create(:request, :started, client: client, provider: provider)
      result = described_class.new(request: started_request, provider: provider, reason: "Emergency").call
      expect(result[:success]).to be true
      expect(started_request.reload.state).to eq("rejected")
    end

    context "when payment is held" do
      let(:req) { create(:request, :accepted, client: client, provider: provider) }
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, request: req, card: card) }

      it "refunds the held payment" do
        described_class.new(request: req, provider: provider, reason: "Not available").call
        expect(payment.reload.status).to eq("refunded")
      end
    end

    it "notifies the client" do
      accepted_request = create(:request, :accepted, client: client, provider: provider)
      described_class.new(request: accepted_request, provider: provider, reason: "Not available").call
      expect(read_notification_log).to include("event=request_rejected")
    end

    it "fails without a reason" do
      accepted_request = create(:request, :accepted, client: client, provider: provider)
      result = described_class.new(request: accepted_request, provider: provider, reason: "").call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Reject reason is required")
    end

    it "fails for created request" do
      created_request = create(:request, client: client, provider: provider)
      result = described_class.new(request: created_request, provider: provider, reason: "Not available").call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot reject request")
    end
  end
end
