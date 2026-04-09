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

      it "creates an order linked to the request" do
        expect { described_class.new(request: request, provider: provider).call }
          .to change(Order, :count).by(1)
        order = request.reload.order
        expect(order).to be_present
        expect(order.state).to eq("pending")
        expect(order.client).to eq(request.client)
        expect(order.provider).to eq(request.provider)
        expect(order.scheduled_at).to eq(request.scheduled_at)
      end

      it "creates a payment for the order" do
        expect { described_class.new(request: request, provider: provider).call }
          .to change(Payment, :count).by(1)
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
