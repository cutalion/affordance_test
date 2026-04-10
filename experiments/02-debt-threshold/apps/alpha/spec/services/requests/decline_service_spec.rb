require "rails_helper"

RSpec.describe Requests::DeclineService do
  let(:provider) { create(:provider) }
  let(:request) { create(:request, provider: provider) }

  describe "#call" do
    context "with correct provider and reason" do
      it "declines the request" do
        result = described_class.new(request: request, provider: provider, reason: "Not available").call
        expect(result[:success]).to be true
        expect(request.reload).to be_declined
        expect(request.decline_reason).to eq("Not available")
      end

      it "notifies the client" do
        described_class.new(request: request, provider: provider, reason: "Not available").call
        expect(read_notification_log).to include("event=request_declined")
      end
    end

    context "without reason" do
      it "returns error" do
        result = described_class.new(request: request, provider: provider, reason: nil).call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Decline reason is required")
      end
    end
  end
end
