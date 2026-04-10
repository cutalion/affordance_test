require "rails_helper"

RSpec.describe Requests::CreateService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:valid_params) do
    {
      scheduled_at: 3.days.from_now,
      duration_minutes: 120,
      location: "123 Main St",
      notes: "Please bring supplies",
      amount_cents: 350_000,
      currency: "RUB"
    }
  end

  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }

  describe "#call" do
    context "with valid params" do
      it "creates request in pending state" do
        expect(result[:success]).to be true
        expect(result[:request].state).to eq("pending")
      end

      it "creates a pending payment with 10% fee" do
        expect { result }.to change(Payment, :count).by(1)
        payment = result[:request].payment
        expect(payment.status).to eq("pending")
        expect(payment.fee_cents).to eq(35_000)
        expect(payment.amount_cents).to eq(350_000)
      end

      it "notifies the provider" do
        result
        expect(read_notification_log).to include("event=request_created")
      end
    end

    context "with invalid params" do
      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }

      it "returns errors on invalid params" do
        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end
    end
  end
end
