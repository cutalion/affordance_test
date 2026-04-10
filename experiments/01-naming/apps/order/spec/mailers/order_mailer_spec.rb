require "rails_helper"

RSpec.describe OrderMailer, type: :mailer do
  let(:client) { build(:client, email: "client@example.com", name: "Alice") }
  let(:provider) { build(:provider, email: "provider@example.com", name: "Bob") }
  let(:order_id) { 42 }
  let(:payload) { { order_id: order_id } }

  describe "#order_created" do
    let(:mail) { OrderMailer.order_created(provider, payload) }

    it "sends to provider email" do
      expect(mail.to).to eq(["provider@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("New order #42")
    end

    it "has order id in body" do
      expect(mail.body.encoded).to include("42")
    end
  end

  describe "#order_confirmed" do
    let(:mail) { OrderMailer.order_confirmed(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Order #42 confirmed")
    end
  end

  describe "#order_started" do
    let(:mail) { OrderMailer.order_started(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Order #42 started")
    end
  end

  describe "#order_completed" do
    let(:mail) { OrderMailer.order_completed(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Order #42 completed")
    end
  end

  describe "#order_canceled" do
    let(:mail) { OrderMailer.order_canceled(provider, payload) }

    it "sends to provider email" do
      expect(mail.to).to eq(["provider@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Order #42 canceled")
    end
  end

  describe "#order_rejected" do
    let(:mail) { OrderMailer.order_rejected(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Order #42 rejected")
    end
  end

  describe "#review_reminder" do
    let(:mail) { OrderMailer.review_reminder(client, payload) }

    it "sends to client email" do
      expect(mail.to).to eq(["client@example.com"])
    end

    it "has correct subject" do
      expect(mail.subject).to eq("Leave a review for order #42")
    end
  end
end
