require "rails_helper"

RSpec.describe Announcements::CreateService do
  let(:client) { create(:client) }
  let(:valid_params) do
    {
      title: "Need a babysitter",
      description: "For two kids, ages 5 and 7",
      location: "123 Main St",
      scheduled_at: 3.days.from_now,
      duration_minutes: 180,
      budget_cents: 500_000,
      currency: "RUB"
    }
  end

  subject(:result) { described_class.new(client: client, params: valid_params).call }

  describe "#call" do
    context "with valid params" do
      it "creates announcement in draft state" do
        expect(result[:success]).to be true
        expect(result[:announcement].state).to eq("draft")
        expect(result[:announcement].client).to eq(client)
      end

      it "persists the announcement" do
        expect { result }.to change(Announcement, :count).by(1)
      end
    end

    context "with invalid params" do
      let(:valid_params) { { title: nil } }

      it "returns errors" do
        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end
    end
  end
end
