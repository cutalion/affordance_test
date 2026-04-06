require "rails_helper"

RSpec.describe ReviewReminderJob, type: :job do
  describe "#perform" do
    def fulfilled_request_at(time)
      req = create(:request, :fulfilled)
      req.update_columns(completed_at: time)
      req
    end

    it "sends reminders to both client and provider for 24-48h old fulfilled requests" do
      req = fulfilled_request_at(36.hours.ago)

      expect(NotificationService).to receive(:notify).with(req.client, :review_reminder, request_id: req.id)
      expect(NotificationService).to receive(:notify).with(req.provider, :review_reminder, request_id: req.id)

      ReviewReminderJob.perform_now
    end

    it "skips sending reminder to client if client already reviewed" do
      req = fulfilled_request_at(36.hours.ago)
      create(:review, request: req, author: req.client)

      expect(NotificationService).not_to receive(:notify).with(req.client, :review_reminder, anything)
      expect(NotificationService).to receive(:notify).with(req.provider, :review_reminder, request_id: req.id)

      ReviewReminderJob.perform_now
    end

    it "skips sending reminder to provider if provider already reviewed" do
      req = fulfilled_request_at(36.hours.ago)
      create(:review, request: req, author: req.provider)

      expect(NotificationService).to receive(:notify).with(req.client, :review_reminder, request_id: req.id)
      expect(NotificationService).not_to receive(:notify).with(req.provider, :review_reminder, anything)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for requests fulfilled less than 24 hours ago" do
      req = fulfilled_request_at(12.hours.ago)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for requests fulfilled more than 48 hours ago" do
      req = fulfilled_request_at(72.hours.ago)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for non-fulfilled requests" do
      req = create(:request, :accepted)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end
  end
end
