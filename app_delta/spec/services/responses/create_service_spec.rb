require "rails_helper"

RSpec.describe Responses::CreateService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:announcement) { create(:announcement, :published, client: client) }
  let(:valid_params) do
    {
      message: "I am available",
      proposed_amount_cents: 450_000
    }
  end

  subject(:result) { described_class.new(announcement: announcement, provider: provider, params: valid_params).call }

  describe "#call" do
    context "with valid params" do
      it "creates response in pending state" do
        expect(result[:success]).to be true
        expect(result[:response].state).to eq("pending")
        expect(result[:response].provider).to eq(provider)
      end

      it "notifies the client" do
        result
        expect(read_notification_log).to include("event=response_received")
      end
    end

    context "when announcement is not published" do
      let(:announcement) { create(:announcement, client: client) }

      it "returns error" do
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Announcement not published")
      end
    end

    context "when provider already responded" do
      before { create(:response, announcement: announcement, provider: provider) }

      it "returns errors" do
        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end
    end
  end
end
