require "rails_helper"

RSpec.describe Client, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:requests).dependent(:destroy) }
    it { is_expected.to have_many(:cards).dependent(:destroy) }
    it { is_expected.to have_many(:reviews).dependent(:destroy) }
  end

  describe "validations" do
    subject { create(:client) }

    it { is_expected.to validate_presence_of(:email) }
    it "validates email uniqueness" do
      existing = create(:client)
      duplicate = build(:client, email: existing.email)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:api_token) }

    it "validates email format" do
      client = build(:client, email: "invalid-email")
      expect(client).not_to be_valid
      expect(client.errors[:email]).to be_present
    end

    it "accepts valid email format" do
      client = build(:client, email: "valid@example.com")
      expect(client).to be_valid
    end
  end

  describe "api_token generation" do
    it "auto-generates api_token on create" do
      client = create(:client)
      expect(client.api_token).to be_present
    end

    it "does not overwrite existing api_token" do
      token = "myspecialtoken123"
      client = create(:client, api_token: token)
      expect(client.api_token).to eq(token)
    end

    it "generates a unique token for each client" do
      client1 = create(:client)
      client2 = create(:client)
      expect(client1.api_token).not_to eq(client2.api_token)
    end
  end

  describe "#default_card" do
    let(:client) { create(:client) }

    it "returns nil when no cards exist" do
      expect(client.default_card).to be_nil
    end

    it "returns the default card" do
      card = create(:card, client: client, default: true)
      expect(client.default_card).to eq(card)
    end

    it "returns nil when no card is marked as default" do
      create(:card, client: client, default: false)
      expect(client.default_card).to be_nil
    end
  end

  describe "notification_preferences" do
    it "has default notification preferences" do
      client = create(:client)
      expect(client.notification_preferences).to include("push" => true, "sms" => true, "email" => true)
    end
  end
end
