require "rails_helper"

RSpec.describe Provider, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:orders).dependent(:destroy) }
    it { is_expected.to have_many(:reviews).dependent(:destroy) }
  end

  describe "validations" do
    subject { create(:provider) }

    it { is_expected.to validate_presence_of(:email) }
    it "validates email uniqueness" do
      existing = create(:provider)
      duplicate = build(:provider, email: existing.email)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:api_token) }

    it "validates email format" do
      provider = build(:provider, email: "not-an-email")
      expect(provider).not_to be_valid
      expect(provider.errors[:email]).to be_present
    end

    it "validates rating is between 0 and 5" do
      provider = build(:provider, rating: -1)
      expect(provider).not_to be_valid

      provider.rating = 5.1
      expect(provider).not_to be_valid

      provider.rating = 3.5
      expect(provider).to be_valid
    end
  end

  describe "api_token generation" do
    it "auto-generates api_token on create" do
      provider = create(:provider)
      expect(provider.api_token).to be_present
    end

    it "does not overwrite existing api_token" do
      token = "providertoken456"
      provider = create(:provider, api_token: token)
      expect(provider.api_token).to eq(token)
    end
  end

  describe ".active scope" do
    it "returns only active providers" do
      active = create(:provider, active: true)
      inactive = create(:provider, active: false)
      expect(Provider.active).to include(active)
      expect(Provider.active).not_to include(inactive)
    end
  end

  describe "notification_preferences" do
    it "has default notification preferences" do
      provider = create(:provider)
      expect(provider.notification_preferences).to include("push" => true, "sms" => true, "email" => true)
    end
  end
end
