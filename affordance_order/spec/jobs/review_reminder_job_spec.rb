require "rails_helper"

RSpec.describe ReviewReminderJob, type: :job do
  describe "#perform" do
    def completed_order_at(time)
      order = create(:order, :completed)
      order.update_columns(completed_at: time)
      order
    end

    it "sends reminders to both client and provider for 24-48h old completed orders" do
      order = completed_order_at(36.hours.ago)

      expect(NotificationService).to receive(:notify).with(order.client, :review_reminder, order_id: order.id)
      expect(NotificationService).to receive(:notify).with(order.provider, :review_reminder, order_id: order.id)

      ReviewReminderJob.perform_now
    end

    it "skips sending reminder to client if client already reviewed" do
      order = completed_order_at(36.hours.ago)
      create(:review, order: order, author: order.client)

      expect(NotificationService).not_to receive(:notify).with(order.client, :review_reminder, anything)
      expect(NotificationService).to receive(:notify).with(order.provider, :review_reminder, order_id: order.id)

      ReviewReminderJob.perform_now
    end

    it "skips sending reminder to provider if provider already reviewed" do
      order = completed_order_at(36.hours.ago)
      create(:review, order: order, author: order.provider)

      expect(NotificationService).to receive(:notify).with(order.client, :review_reminder, order_id: order.id)
      expect(NotificationService).not_to receive(:notify).with(order.provider, :review_reminder, anything)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for orders completed less than 24 hours ago" do
      order = completed_order_at(12.hours.ago)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for orders completed more than 48 hours ago" do
      order = completed_order_at(72.hours.ago)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for non-completed orders" do
      order = create(:order, :confirmed)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end
  end
end
