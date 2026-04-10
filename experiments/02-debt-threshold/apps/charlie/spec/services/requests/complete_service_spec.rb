require "rails_helper"

RSpec.describe Requests::CompleteService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:request) { create(:request, :in_progress, client: client, provider: provider) }

  describe "#call" do
    it "completes an in_progress request" do
      result = described_class.new(request: request, provider: provider).call
      expect(result[:success]).to be true
      expect(request.reload.state).to eq("completed")
    end

    context "when payment is held" do
      let!(:card) { create(:card, :default, client: client) }
      let!(:payment) { create(:payment, :held, request: request, card: card) }

      it "charges the held payment" do
        described_class.new(request: request, provider: provider).call
        expect(payment.reload.status).to eq("charged")
      end
    end

    it "notifies both client and provider" do
      described_class.new(request: request, provider: provider).call
      log = read_notification_log
      expect(log).to include("client_#{request.client_id}")
      expect(log).to include("provider_#{request.provider_id}")
      expect(log).to include("event=request_completed")
    end

    it "fails for wrong provider" do
      result = described_class.new(request: request, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your request")
    end
  end
end
