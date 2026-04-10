require "rails_helper"

RSpec.describe RequestMailer, type: :mailer do
  let(:client) { build(:client, email: "client@example.com", name: "Alice") }
  let(:provider) { build(:provider, email: "provider@example.com", name: "Bob") }
  let(:request_id) { 42 }
  let(:payload) { { request_id: request_id } }

  describe "#request_created" do
    let(:mail) { RequestMailer.request_created(provider, payload) }

    it "sends to provider email" do
      expect(mail.to).to eq(["provider@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("New request #42")
    end

    it "has request id in body" do
      expect(mail.body.encoded).to include("42")
    end
  end

  describe "#request_created_accepted" do
    let(:mail) { RequestMailer.request_created_accepted(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Request #42 created and accepted")
    end
  end

  describe "#request_accepted" do
    let(:mail) { RequestMailer.request_accepted(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Request #42 accepted")
    end
  end

  describe "#request_declined" do
    let(:mail) { RequestMailer.request_declined(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Request #42 declined")
    end
  end

  describe "#request_started" do
    let(:mail) { RequestMailer.request_started(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Request #42 started")
    end
  end

  describe "#request_fulfilled" do
    let(:mail) { RequestMailer.request_fulfilled(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Request #42 fulfilled")
    end
  end

  describe "#request_canceled" do
    let(:mail) { RequestMailer.request_canceled(provider, payload) }

    it "sends to provider email" do
      expect(mail.to).to eq(["provider@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Request #42 canceled")
    end
  end

  describe "#request_rejected" do
    let(:mail) { RequestMailer.request_rejected(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Request #42 rejected")
    end
  end

  describe "#review_reminder" do
    let(:mail) { RequestMailer.review_reminder(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Leave a review for request #42")
    end
  end
end
