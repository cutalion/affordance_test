require "rails_helper"

RSpec.describe Request, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:client) }
    it { is_expected.to belong_to(:provider) }
  end

  describe "validations" do
    subject { build(:request) }

    it { is_expected.to validate_presence_of(:scheduled_at) }
    it { is_expected.to validate_presence_of(:duration_minutes) }

    it "validates duration_minutes is greater than 0" do
      request = build(:request, duration_minutes: 0)
      expect(request).not_to be_valid
    end

    context "when declined" do
      it "requires decline_reason" do
        request = build(:request, :declined, decline_reason: nil)
        expect(request).not_to be_valid
      end
    end
  end

  describe "state machine" do
    let(:request) { create(:request) }

    it "has initial state of pending" do
      expect(request.state).to eq("pending")
      expect(request).to be_pending
    end

    describe "accept event" do
      it "transitions from pending to accepted" do
        request.accept!
        expect(request).to be_accepted
      end

      it "sets accepted_at timestamp" do
        freeze_time do
          request.accept!
          expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
        end
      end

      it "cannot accept from other states" do
        request.accept!
        expect { request.accept! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "decline event" do
      it "transitions from pending to declined" do
        request.update!(decline_reason: "Not available")
        request.decline!
        expect(request).to be_declined
      end

      it "cannot decline from accepted" do
        request.accept!
        expect { request.decline! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "expire event" do
      it "transitions from pending to expired" do
        request.expire!
        expect(request).to be_expired
      end

      it "sets expired_at timestamp" do
        freeze_time do
          request.expire!
          expect(request.reload.expired_at).to be_within(1.second).of(Time.current)
        end
      end
    end
  end

  describe "scopes" do
    let!(:future_request) { create(:request, scheduled_at: 1.day.from_now) }
    let!(:past_request) { create(:request, scheduled_at: 1.day.ago) }
    let!(:accepted_request) { create(:request, :accepted) }

    describe ".upcoming" do
      it "returns requests with scheduled_at in the future" do
        expect(Request.upcoming).to include(future_request)
        expect(Request.upcoming).not_to include(past_request)
      end
    end

    describe ".by_state" do
      it "filters by state" do
        expect(Request.by_state("accepted")).to include(accepted_request)
        expect(Request.by_state("accepted")).not_to include(future_request)
      end
    end
  end
end
