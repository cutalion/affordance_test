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

      it "creates a payment for the request" do
        expect { described_class.new(request: request, provider: provider).call }
          .to change(Payment, :count).by(1)
        payment = request.reload.payment
        expect(payment).to be_present
        expect(payment.amount_cents).to eq(request.amount_cents)
        expect(payment.status).to eq("pending")
      end

      it "calculates fee as 10% of amount" do
        described_class.new(request: request, provider: provider).call
        expect(request.reload.payment.fee_cents).to eq(35_000)
      end

      context "when client has a default card" do
        let!(:card) { create(:card, :default, client: request.client) }

        it "holds the payment" do
          described_class.new(request: request, provider: provider).call
          expect(request.reload.payment.status).to eq("held")
        end
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
