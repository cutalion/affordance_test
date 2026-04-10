require "rails_helper"

RSpec.describe Announcements::CloseService do
  let(:client) { create(:client) }
  let(:announcement) { create(:announcement, :published, client: client) }

  subject(:result) { described_class.new(announcement: announcement, client: client).call }

  describe "#call" do
    context "with valid published announcement" do
      it "closes the announcement" do
        expect(result[:success]).to be true
        expect(result[:announcement]).to be_closed
      end

      it "sets closed_at" do
        freeze_time do
          result
          expect(announcement.reload.closed_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "when announcement is in draft state" do
      let(:announcement) { create(:announcement, client: client) }

      it "returns error" do
        expect(result[:success]).to be false
        expect(result[:error]).to include("Cannot close")
      end
    end

    context "when client does not own announcement" do
      let(:other_client) { create(:client) }
      subject(:result) { described_class.new(announcement: announcement, client: other_client).call }

      it "returns error" do
        expect(result[:success]).to be false
        expect(result[:error]).to eq("Not your announcement")
      end
    end
  end
end
