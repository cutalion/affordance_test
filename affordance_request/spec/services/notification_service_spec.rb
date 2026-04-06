require "rails_helper"

RSpec.describe NotificationService do
  let(:client) { create(:client, notification_preferences: { "push" => true, "sms" => true, "email" => true }) }

  describe ".notify" do
    context "when all preferences are enabled" do
      it "writes push log entry" do
        NotificationService.notify(client, :request_created, request_id: 1)
        expect(read_notification_log).to include("[PUSH]")
        expect(read_notification_log).to include("event=request_created")
      end

      it "writes SMS log entry" do
        NotificationService.notify(client, :request_created, request_id: 1)
        expect(read_notification_log).to include("[SMS]")
        expect(read_notification_log).to include("to=#{client.phone}")
      end

      it "writes email log entry" do
        NotificationService.notify(client, :request_created, request_id: 1)
        expect(read_notification_log).to include("[EMAIL]")
        expect(read_notification_log).to include("to=#{client.email}")
      end
    end

    context "when push is disabled" do
      let(:client) { create(:client, notification_preferences: { "push" => false, "sms" => true, "email" => true }) }

      it "does not write push log entry" do
        NotificationService.notify(client, :request_created, request_id: 1)
        expect(read_notification_log).not_to include("[PUSH]")
      end
    end

    context "when sms is disabled" do
      let(:client) { create(:client, notification_preferences: { "push" => true, "sms" => false, "email" => true }) }

      it "does not write SMS log entry" do
        NotificationService.notify(client, :request_created, request_id: 1)
        expect(read_notification_log).not_to include("[SMS]")
      end
    end

    context "when email is disabled" do
      let(:client) { create(:client, notification_preferences: { "push" => true, "sms" => true, "email" => false }) }

      it "does not write email log entry" do
        NotificationService.notify(client, :request_created, request_id: 1)
        expect(read_notification_log).not_to include("[EMAIL]")
      end
    end
  end
end
