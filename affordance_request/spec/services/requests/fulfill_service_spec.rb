require "rails_helper"

RSpec.describe Requests::FulfillService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:req) { create(:request, :started, client: client, provider: provider) }

  describe "#call" do
    it "fulfills a started request" do
      result = described_class.new(request: req, provider: provider).call
      expect(result[:success]).to be true
      expect(req.reload.state).to eq("fulfilled")
    end

    context "when payment is held" do
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, request: req, card: card) }

      it "charges the held payment" do
        described_class.new(request: req, provider: provider).call
        expect(payment.reload.status).to eq("charged")
      end
    end

    it "notifies both client and provider" do
      described_class.new(request: req, provider: provider).call
      log = read_notification_log
      expect(log).to include("client_#{req.client_id}")
      expect(log).to include("provider_#{req.provider_id}")
      expect(log).to include("event=request_fulfilled")
    end

    it "fails for wrong provider" do
      result = described_class.new(request: req, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your request")
    end
  end
end
