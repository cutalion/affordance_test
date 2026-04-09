require "rails_helper"

RSpec.describe Announcements::PublishService do
  let(:client) { create(:client) }
  let(:announcement) { create(:announcement, client: client) }

  describe "#call" do
    context "with correct client" do
      it "publishes the announcement" do
        result = described_class.new(announcement: announcement, client: client).call
        expect(result[:success]).to be true
        expect(announcement.reload).to be_published
      end
    end

    context "with wrong client" do
      let(:other_client) { create(:client) }

      it "returns error" do
        result = described_class.new(announcement: announcement, client: other_client).call
        expect(result[:success]).to be false
        expect(result[:error]).to include("Not your announcement")
      end
    end

    context "when already published" do
      let(:announcement) { create(:announcement, :published, client: client) }

      it "returns error" do
        result = described_class.new(announcement: announcement, client: client).call
        expect(result[:success]).to be false
      end
    end
  end
end
