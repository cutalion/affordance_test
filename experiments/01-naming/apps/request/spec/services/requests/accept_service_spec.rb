require "rails_helper"

RSpec.describe Requests::AcceptService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:req) { create(:request, client: client, provider: provider) }

  describe "#call" do
    it "accepts a created request" do
      result = described_class.new(request: req, provider: provider).call
      expect(result[:success]).to be true
      expect(req.reload.state).to eq("accepted")
    end

    it "notifies the client" do
      described_class.new(request: req, provider: provider).call
      expect(read_notification_log).to include("event=request_accepted")
    end

    it "fails for wrong provider" do
      result = described_class.new(request: req, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your request")
    end

    it "fails for non-created request" do
      req.update!(state: "accepted")
      result = described_class.new(request: req, provider: provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot accept request")
    end
  end
end
