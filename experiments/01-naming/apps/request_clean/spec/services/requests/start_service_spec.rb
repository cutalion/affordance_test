require "rails_helper"

RSpec.describe Requests::StartService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:request) { create(:request, :confirmed, client: client, provider: provider) }

  describe "#call" do
    it "starts a confirmed request" do
      result = described_class.new(request: request, provider: provider).call
      expect(result[:success]).to be true
      expect(request.reload.state).to eq("in_progress")
    end

    it "notifies the client" do
      described_class.new(request: request, provider: provider).call
      expect(read_notification_log).to include("event=request_started")
    end

    it "fails for wrong provider" do
      result = described_class.new(request: request, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your request")
    end

    it "fails for pending request" do
      pending_request = create(:request, client: client, provider: provider)
      result = described_class.new(request: pending_request, provider: provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot start request")
    end
  end
end
