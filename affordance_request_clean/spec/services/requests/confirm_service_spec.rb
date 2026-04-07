require "rails_helper"

RSpec.describe Requests::ConfirmService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:other_provider) { create(:provider) }
  let(:request) { create(:request, client: client, provider: provider) }

  describe "#call" do
    it "confirms a pending request" do
      result = described_class.new(request: request, provider: provider).call
      expect(result[:success]).to be true
      expect(request.reload.state).to eq("confirmed")
    end

    it "notifies the client" do
      described_class.new(request: request, provider: provider).call
      expect(read_notification_log).to include("event=request_confirmed")
    end

    it "fails for wrong provider" do
      result = described_class.new(request: request, provider: other_provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Not your request")
    end

    it "fails for non-pending request" do
      request.update!(state: "confirmed")
      result = described_class.new(request: request, provider: provider).call
      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot confirm request")
    end
  end
end
