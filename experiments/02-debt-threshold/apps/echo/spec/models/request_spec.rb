require "rails_helper"

RSpec.describe Request, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:client) }
    it { is_expected.to belong_to(:provider) }
    it { is_expected.to have_one(:payment).dependent(:destroy) }
    it { is_expected.to have_many(:reviews).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:request) }

    it { is_expected.to validate_presence_of(:scheduled_at) }
    it { is_expected.to validate_presence_of(:duration_minutes) }
    it { is_expected.to validate_presence_of(:amount_cents) }
    it { is_expected.to validate_presence_of(:currency) }

    it "validates duration_minutes is greater than 0" do
      request = build(:request, duration_minutes: 0)
      expect(request).not_to be_valid
    end

    it "validates amount_cents is >= 0" do
      request = build(:request, amount_cents: -1)
      expect(request).not_to be_valid

      request.amount_cents = 0
      expect(request).to be_valid
    end

    context "when declined" do
      it "requires decline_reason" do
        request = build(:request, :declined, decline_reason: nil)
        expect(request).not_to be_valid
      end
    end

    context "when canceled" do
      it "requires cancel_reason" do
        request = build(:request, :canceled, cancel_reason: nil)
        expect(request).not_to be_valid
        expect(request.errors[:cancel_reason]).to be_present
      end
    end

    context "when rejected" do
      it "requires reject_reason" do
        request = build(:request, :rejected, reject_reason: nil)
        expect(request).not_to be_valid
        expect(request.errors[:reject_reason]).to be_present
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

    describe "start event" do
      before { request.accept! }

      it "transitions from accepted to in_progress" do
        request.start!
        expect(request).to be_in_progress
      end

      it "sets started_at timestamp" do
        freeze_time do
          request.start!
          expect(request.reload.started_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "complete event" do
      before { request.accept!; request.start! }

      it "transitions from in_progress to completed" do
        request.complete!
        expect(request).to be_completed
      end

      it "sets completed_at timestamp" do
        freeze_time do
          request.complete!
          expect(request.reload.completed_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "cancel event" do
      it "transitions from pending to canceled" do
        request.update!(cancel_reason: "Changed my mind")
        request.cancel!
        expect(request).to be_canceled
      end

      it "transitions from accepted to canceled" do
        request.accept!
        request.update!(cancel_reason: "Changed my mind")
        request.cancel!
        expect(request).to be_canceled
      end

      it "cannot cancel from in_progress" do
        request.accept!
        request.start!
        expect { request.cancel! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "reject event" do
      it "transitions from accepted to rejected" do
        request.accept!
        request.update!(reject_reason: "Cannot make it")
        request.reject!
        expect(request).to be_rejected
      end

      it "transitions from in_progress to rejected" do
        request.accept!
        request.start!
        request.update!(reject_reason: "Emergency")
        request.reject!
        expect(request).to be_rejected
      end

      it "cannot reject from pending" do
        expect { request.reject! }.to raise_error(AASM::InvalidTransition)
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

    describe ".past" do
      it "returns requests with scheduled_at in the past" do
        expect(Request.past).to include(past_request)
        expect(Request.past).not_to include(future_request)
      end
    end

    describe ".by_state" do
      it "filters by state" do
        expect(Request.by_state("accepted")).to include(accepted_request)
        expect(Request.by_state("accepted")).not_to include(future_request)
      end

      it "returns all when state is blank" do
        expect(Request.by_state(nil).count).to eq(Request.count)
      end
    end

    describe ".sorted" do
      it "returns requests sorted by scheduled_at descending" do
        sorted = Request.sorted.to_a
        expect(sorted.first.scheduled_at).to be >= sorted.last.scheduled_at
      end
    end
  end
end
