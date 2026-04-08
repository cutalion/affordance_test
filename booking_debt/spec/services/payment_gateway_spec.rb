require "rails_helper"

RSpec.describe PaymentGateway do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:request) { create(:request, client: client, provider: provider) }
  let(:payment) { create(:payment, request: request, amount_cents: 350_000) }

  describe ".hold" do
    context "when client has a default card" do
      let!(:card) { create(:card, :default, client: client) }

      it "returns success" do
        result = PaymentGateway.hold(payment)
        expect(result[:success]).to be true
      end

      it "updates payment status to held" do
        PaymentGateway.hold(payment)
        expect(payment.reload.status).to eq("held")
      end

      it "assigns the card to the payment" do
        PaymentGateway.hold(payment)
        expect(payment.reload.card).to eq(card)
      end

      it "writes to payment log" do
        PaymentGateway.hold(payment)
        expect(read_payment_log).to include("[PAYMENT] action=hold")
        expect(read_payment_log).to include("payment_id=#{payment.id}")
      end
    end

    context "when client has no default card" do
      it "returns failure" do
        result = PaymentGateway.hold(payment)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("No default card")
      end
    end
  end

  describe ".charge" do
    context "when payment is held" do
      let(:card) { create(:card, :default, client: client) }
      let(:payment) { create(:payment, :held, request: request, card: card) }

      it "returns success" do
        result = PaymentGateway.charge(payment)
        expect(result[:success]).to be true
      end

      it "updates payment status to charged" do
        PaymentGateway.charge(payment)
        expect(payment.reload.status).to eq("charged")
      end

      it "writes to payment log" do
        PaymentGateway.charge(payment)
        expect(read_payment_log).to include("[PAYMENT] action=charge")
        expect(read_payment_log).to include("payment_id=#{payment.id}")
      end
    end

    context "when payment is not held" do
      it "returns failure" do
        result = PaymentGateway.charge(payment)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Payment not held")
      end
    end
  end

  describe ".refund" do
    context "when payment is charged" do
      let(:card) { create(:card, :default, client: client) }
      let(:payment) { create(:payment, :charged, request: request, card: card) }

      it "returns success" do
        result = PaymentGateway.refund(payment)
        expect(result[:success]).to be true
      end

      it "updates payment status to refunded" do
        PaymentGateway.refund(payment)
        expect(payment.reload.status).to eq("refunded")
      end

      it "writes to payment log" do
        PaymentGateway.refund(payment)
        expect(read_payment_log).to include("[PAYMENT] action=refund")
        expect(read_payment_log).to include("payment_id=#{payment.id}")
      end
    end

    context "when payment is held" do
      let(:card) { create(:card, :default, client: client) }
      let(:payment) { create(:payment, :held, request: request, card: card) }

      it "returns success" do
        result = PaymentGateway.refund(payment)
        expect(result[:success]).to be true
      end
    end

    context "when payment is pending" do
      it "returns failure" do
        result = PaymentGateway.refund(payment)
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Payment not chargeable")
      end
    end
  end
end
