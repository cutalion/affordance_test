require "rails_helper"

RSpec.describe PaymentHoldJob, type: :job do
  describe "#perform" do
    it "holds payment for tomorrow's pending orders" do
      order = create(:order, :with_payment, :with_card, :scheduled_tomorrow, state: "pending")
      expect(order.payment.status).to eq("pending")

      PaymentHoldJob.perform_now

      expect(order.payment.reload.status).to eq("held")
    end

    it "holds payment for tomorrow's confirmed orders" do
      order = create(:order, :with_payment, :with_card, :scheduled_tomorrow, state: "confirmed")

      PaymentHoldJob.perform_now

      expect(order.payment.reload.status).to eq("held")
    end

    it "skips orders scheduled far in the future (beyond 24 hours)" do
      order = create(:order, :with_payment, scheduled_at: 3.days.from_now, state: "pending")
      create(:card, client: order.client, default: true)

      PaymentHoldJob.perform_now

      expect(order.payment.reload.status).to eq("pending")
    end

    it "skips payments that are already held" do
      client = create(:client)
      card = create(:card, client: client, default: true)
      order = create(:order, client: client, scheduled_at: 12.hours.from_now, state: "confirmed")
      payment = create(:payment, :held, order: order, card: card)

      PaymentHoldJob.perform_now

      expect(payment.reload.status).to eq("held")
    end

    it "skips canceled orders" do
      order = create(:order, :canceled, :with_payment, :with_card, scheduled_at: 12.hours.from_now)

      PaymentHoldJob.perform_now

      expect(order.payment.reload.status).to eq("pending")
    end

    it "handles orders with no default card gracefully" do
      order = create(:order, :with_payment, :scheduled_tomorrow, state: "pending")
      # No card created for this client

      expect { PaymentHoldJob.perform_now }.not_to raise_error
      expect(order.payment.reload.status).to eq("pending")
    end
  end
end
