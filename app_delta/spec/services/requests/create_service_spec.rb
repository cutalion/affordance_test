require "rails_helper"

RSpec.describe Requests::CreateService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:valid_params) do
    {
      scheduled_at: 3.days.from_now,
      duration_minutes: 120,
      location: "123 Main St",
      notes: "Please bring supplies"
    }
  end

  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }

  describe "#call" do
    context "with valid params" do
      it "creates request in pending state" do
        expect(result[:success]).to be true
        expect(result[:request].state).to eq("pending")
      end

      it "notifies the provider" do
        result
        expect(read_notification_log).to include("event=request_created")
      end
    end

    context "with invalid params" do
      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil } }

      it "returns errors" do
        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end
    end
  end
end
