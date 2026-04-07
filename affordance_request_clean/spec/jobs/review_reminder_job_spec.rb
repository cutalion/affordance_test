require "rails_helper"

RSpec.describe ReviewReminderJob, type: :job do
  describe "#perform" do
    def completed_request_at(time)
      request = create(:request, :completed)
      request.update_columns(completed_at: time)
      request
    end

    it "sends reminders to both client and provider for 24-48h old completed requests" do
      request = completed_request_at(36.hours.ago)

      expect(NotificationService).to receive(:notify).with(request.client, :review_reminder, request_id: request.id)
      expect(NotificationService).to receive(:notify).with(request.provider, :review_reminder, request_id: request.id)

      ReviewReminderJob.perform_now
    end

    it "skips sending reminder to client if client already reviewed" do
      request = completed_request_at(36.hours.ago)
      create(:review, request: request, author: request.client)

      expect(NotificationService).not_to receive(:notify).with(request.client, :review_reminder, anything)
      expect(NotificationService).to receive(:notify).with(request.provider, :review_reminder, request_id: request.id)

      ReviewReminderJob.perform_now
    end

    it "skips sending reminder to provider if provider already reviewed" do
      request = completed_request_at(36.hours.ago)
      create(:review, request: request, author: request.provider)

      expect(NotificationService).to receive(:notify).with(request.client, :review_reminder, request_id: request.id)
      expect(NotificationService).not_to receive(:notify).with(request.provider, :review_reminder, anything)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for requests completed less than 24 hours ago" do
      request = completed_request_at(12.hours.ago)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for requests completed more than 48 hours ago" do
      request = completed_request_at(72.hours.ago)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end

    it "does not send reminders for non-completed requests" do
      request = create(:request, :confirmed)

      expect(NotificationService).not_to receive(:notify)

      ReviewReminderJob.perform_now
    end
  end
end
