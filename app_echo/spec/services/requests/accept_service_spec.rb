require "rails_helper"

RSpec.describe Requests::AcceptService do
  describe "direct invitation flow" do
    let(:provider) { create(:provider) }
    let(:request) { create(:request, provider: provider) }

    context "with correct provider as actor" do
      it "accepts the request" do
        result = described_class.new(request: request, actor: provider).call
        expect(result[:success]).to be true
        expect(request.reload).to be_accepted
      end

      it "creates a payment for the request" do
        expect { described_class.new(request: request, actor: provider).call }
          .to change(Payment, :count).by(1)
        payment = request.reload.payment
        expect(payment).to be_present
        expect(payment.amount_cents).to eq(request.amount_cents)
        expect(payment.status).to eq("pending")
      end

      it "calculates fee as 10% of amount" do
        described_class.new(request: request, actor: provider).call
        expect(request.reload.payment.fee_cents).to eq(35_000)
      end

      context "when client has a default card" do
        let!(:card) { create(:card, :default, client: request.client) }

        it "holds the payment" do
          described_class.new(request: request, actor: provider).call
          expect(request.reload.payment.status).to eq("held")
        end
      end

      it "notifies the client" do
        described_class.new(request: request, actor: provider).call
        expect(read_notification_log).to include("event=request_accepted")
      end
    end

    context "with wrong provider" do
      let(:other_provider) { create(:provider) }

      it "returns error" do
        result = described_class.new(request: request, actor: other_provider).call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Not your request")
      end
    end

    context "when already accepted" do
      before { request.accept! }

      it "returns error" do
        result = described_class.new(request: request, actor: provider).call
        expect(result[:success]).to be false
      end
    end
  end

  describe "announcement response flow" do
    let(:client) { create(:client) }
    let(:announcement) { create(:announcement, :published, client: client) }
    let(:provider) { create(:provider) }
    let(:request) do
      create(:request,
        client: client,
        provider: provider,
        announcement: announcement,
        proposed_amount_cents: 400_000,
        response_message: "I can help"
      )
    end

    context "with correct client as actor" do
      it "accepts the request" do
        result = described_class.new(request: request, actor: client).call
        expect(result[:success]).to be true
        expect(request.reload).to be_accepted
      end

      it "creates a payment using proposed_amount_cents" do
        described_class.new(request: request, actor: client).call
        payment = request.reload.payment
        expect(payment.amount_cents).to eq(400_000)
      end

      it "falls back to announcement budget_cents when no proposed amount" do
        request.update!(proposed_amount_cents: nil)
        described_class.new(request: request, actor: client).call
        payment = request.reload.payment
        expect(payment.amount_cents).to eq(announcement.budget_cents)
      end

      it "declines other pending responses" do
        other_request = create(:request,
          client: client,
          provider: create(:provider),
          announcement: announcement,
          response_message: "Me too"
        )

        described_class.new(request: request, actor: client).call
        expect(other_request.reload).to be_declined
        expect(other_request.decline_reason).to eq("Another provider was selected")
      end

      it "closes the announcement" do
        described_class.new(request: request, actor: client).call
        expect(announcement.reload).to be_closed
      end

      it "notifies the provider" do
        described_class.new(request: request, actor: client).call
        expect(read_notification_log).to include("event=request_accepted")
      end

      context "when client has a default card" do
        let!(:card) { create(:card, :default, client: client) }

        it "holds the payment" do
          described_class.new(request: request, actor: client).call
          expect(request.reload.payment.status).to eq("held")
        end
      end
    end

    context "with wrong client" do
      let(:other_client) { create(:client) }

      it "returns error" do
        result = described_class.new(request: request, actor: other_client).call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Not your announcement")
      end
    end
  end
end
