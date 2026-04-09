require "rails_helper"

RSpec.describe Responses::SelectService do
  let(:client) { create(:client) }
  let(:provider1) { create(:provider) }
  let(:provider2) { create(:provider) }
  let(:announcement) { create(:announcement, :published, client: client, budget_cents: 500_000) }
  let(:response1) { create(:response, announcement: announcement, provider: provider1, proposed_amount_cents: 450_000) }
  let(:response2) { create(:response, announcement: announcement, provider: provider2, proposed_amount_cents: 400_000) }

  subject(:result) { described_class.new(response: response1, client: client).call }

  describe "#call" do
    before { response2 } # ensure both responses exist

    context "with valid selection" do
      it "selects the response" do
        expect(result[:success]).to be true
        expect(result[:response]).to be_selected
      end

      it "rejects other pending responses" do
        result
        expect(response2.reload).to be_rejected
      end

      it "creates an order" do
        expect { result }.to change(Order, :count).by(1)
      end

      it "creates order with correct attributes" do
        result
        order = Order.last
        expect(order.client).to eq(client)
        expect(order.provider).to eq(provider1)
        expect(order.amount_cents).to eq(450_000)
        expect(order.notes).to include(announcement.title)
      end

      it "closes the announcement" do
        result
        expect(announcement.reload).to be_closed
      end

      it "notifies the selected provider" do
        result
        expect(read_notification_log).to include("event=response_selected")
      end
    end

    context "when client does not own announcement" do
      let(:other_client) { create(:client) }
      subject(:result) { described_class.new(response: response1, client: other_client).call }

      it "returns error" do
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Not your announcement")
      end
    end

    context "when response is already selected" do
      before { response1.select! }

      it "returns error" do
        expect(result[:success]).to be false
        expect(result[:error]).to include("Cannot select")
      end
    end
  end
end
