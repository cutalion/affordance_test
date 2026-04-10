require "rails_helper"

RSpec.describe Responses::RejectService do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:announcement) { create(:announcement, :published, client: client) }
  let(:response) { create(:response, announcement: announcement, provider: provider) }

  subject(:result) { described_class.new(response: response, client: client).call }

  describe "#call" do
    context "with valid rejection" do
      it "rejects the response" do
        expect(result[:success]).to be true
        expect(result[:response]).to be_rejected
      end

      it "notifies the provider" do
        result
        expect(read_notification_log).to include("event=response_rejected")
      end
    end

    context "when client does not own announcement" do
      let(:other_client) { create(:client) }
      subject(:result) { described_class.new(response: response, client: other_client).call }

      it "returns error" do
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Not your announcement")
      end
    end

    context "when response is already rejected" do
      before { response.reject! }

      it "returns error" do
        expect(result[:success]).to be false
        expect(result[:error]).to include("Cannot reject")
      end
    end
  end
end
