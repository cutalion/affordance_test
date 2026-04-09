require "rails_helper"

RSpec.describe Announcement, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:client) }
    it { is_expected.to have_many(:responses).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:announcement) }

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:currency) }
  end

  describe "state machine" do
    let(:announcement) { create(:announcement) }

    it "has initial state of draft" do
      expect(announcement.state).to eq("draft")
      expect(announcement).to be_draft
    end

    describe "publish event" do
      it "transitions from draft to published" do
        announcement.publish!
        expect(announcement).to be_published
      end

      it "sets published_at timestamp" do
        freeze_time do
          announcement.publish!
          expect(announcement.reload.published_at).to be_within(1.second).of(Time.current)
        end
      end

      it "cannot publish from published state" do
        announcement.publish!
        expect { announcement.publish! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "close event" do
      before { announcement.publish! }

      it "transitions from published to closed" do
        announcement.close!
        expect(announcement).to be_closed
      end

      it "sets closed_at timestamp" do
        freeze_time do
          announcement.close!
          expect(announcement.reload.closed_at).to be_within(1.second).of(Time.current)
        end
      end

      it "cannot close from draft state" do
        draft_announcement = create(:announcement)
        expect { draft_announcement.close! }.to raise_error(AASM::InvalidTransition)
      end
    end
  end

  describe "scopes" do
    let!(:draft_announcement) { create(:announcement) }
    let!(:published_announcement) { create(:announcement, :published) }

    describe ".by_state" do
      it "filters by state" do
        expect(Announcement.by_state("published")).to include(published_announcement)
        expect(Announcement.by_state("published")).not_to include(draft_announcement)
      end

      it "returns all when state is blank" do
        expect(Announcement.by_state(nil).count).to eq(Announcement.count)
      end
    end

    describe ".sorted" do
      it "returns announcements sorted by created_at descending" do
        sorted = Announcement.sorted.to_a
        expect(sorted.first.created_at).to be >= sorted.last.created_at
      end
    end
  end
end
