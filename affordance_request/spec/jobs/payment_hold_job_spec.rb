require "rails_helper"

RSpec.describe PaymentHoldJob, type: :job do
  describe "#perform" do
    it "holds payment for tomorrow's created requests" do
      req = create(:request, :with_payment, :with_card, :scheduled_tomorrow, state: "created")
      expect(req.payment.status).to eq("pending")

      PaymentHoldJob.perform_now

      expect(req.payment.reload.status).to eq("held")
    end

    it "holds payment for tomorrow's accepted requests" do
      req = create(:request, :with_payment, :with_card, :scheduled_tomorrow, state: "accepted")

      PaymentHoldJob.perform_now

      expect(req.payment.reload.status).to eq("held")
    end

    it "holds payment for tomorrow's created_accepted requests" do
      req = create(:request, :with_payment, :with_card, :scheduled_tomorrow, state: "created_accepted")

      PaymentHoldJob.perform_now

      expect(req.payment.reload.status).to eq("held")
    end

    it "skips requests scheduled far in the future (beyond 24 hours)" do
      req = create(:request, :with_payment, scheduled_at: 3.days.from_now, state: "created")
      create(:card, client: req.client, default: true)

      PaymentHoldJob.perform_now

      expect(req.payment.reload.status).to eq("pending")
    end

    it "skips payments that are already held" do
      client = create(:client)
      card = create(:card, client: client, default: true)
      req = create(:request, client: client, scheduled_at: 12.hours.from_now, state: "accepted")
      payment = create(:payment, :held, request: req, card: card)

      PaymentHoldJob.perform_now

      expect(payment.reload.status).to eq("held")
    end

    it "skips canceled requests" do
      req = create(:request, :canceled, :with_payment, :with_card, scheduled_at: 12.hours.from_now)

      PaymentHoldJob.perform_now

      expect(req.payment.reload.status).to eq("pending")
    end

    it "handles requests with no default card gracefully" do
      req = create(:request, :with_payment, :scheduled_tomorrow, state: "created")
      # No card created for this client

      expect { PaymentHoldJob.perform_now }.not_to raise_error
      expect(req.payment.reload.status).to eq("pending")
    end
  end
end
