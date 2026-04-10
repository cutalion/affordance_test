require "rails_helper"

RSpec.describe PaymentHoldJob, type: :job do
  describe "#perform" do
    it "holds payment for tomorrow's pending requests" do
      request = create(:request, :with_payment, :with_card, :scheduled_tomorrow, state: "pending")
      expect(request.payment.status).to eq("pending")

      PaymentHoldJob.perform_now

      expect(request.payment.reload.status).to eq("held")
    end

    it "holds payment for tomorrow's confirmed requests" do
      request = create(:request, :with_payment, :with_card, :scheduled_tomorrow, state: "confirmed")

      PaymentHoldJob.perform_now

      expect(request.payment.reload.status).to eq("held")
    end

    it "skips requests scheduled far in the future (beyond 24 hours)" do
      request = create(:request, :with_payment, scheduled_at: 3.days.from_now, state: "pending")
      create(:card, client: request.client, default: true)

      PaymentHoldJob.perform_now

      expect(request.payment.reload.status).to eq("pending")
    end

    it "skips payments that are already held" do
      client = create(:client)
      card = create(:card, client: client, default: true)
      request = create(:request, client: client, scheduled_at: 12.hours.from_now, state: "confirmed")
      payment = create(:payment, :held, request: request, card: card)

      PaymentHoldJob.perform_now

      expect(payment.reload.status).to eq("held")
    end

    it "skips canceled requests" do
      request = create(:request, :canceled, :with_payment, :with_card, scheduled_at: 12.hours.from_now)

      PaymentHoldJob.perform_now

      expect(request.payment.reload.status).to eq("pending")
    end

    it "handles requests with no default card gracefully" do
      request = create(:request, :with_payment, :scheduled_tomorrow, state: "pending")
      # No card created for this client

      expect { PaymentHoldJob.perform_now }.not_to raise_error
      expect(request.payment.reload.status).to eq("pending")
    end
  end
end
