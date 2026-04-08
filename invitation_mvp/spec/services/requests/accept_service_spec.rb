require "rails_helper"

RSpec.describe Requests::AcceptService do
  let(:provider) { create(:provider) }
  let(:request) { create(:request, provider: provider) }

  describe "#call" do
    context "with correct provider" do
      it "accepts the request" do
        result = described_class.new(request: request, provider: provider).call
        expect(result[:success]).to be true
        expect(request.reload).to be_accepted
      end

      it "notifies the client" do
        described_class.new(request: request, provider: provider).call
        expect(read_notification_log).to include("event=request_accepted")
      end
    end

    context "with wrong provider" do
      let(:other_provider) { create(:provider) }

      it "returns error" do
        result = described_class.new(request: request, provider: other_provider).call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Not your request")
      end
    end

    context "when already accepted" do
      before { request.accept! }

      it "returns error" do
        result = described_class.new(request: request, provider: provider).call
        expect(result[:success]).to be false
      end
    end
  end
end
