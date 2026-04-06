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
      req = build(:request, duration_minutes: 0)
      expect(req).not_to be_valid
      expect(req.errors[:duration_minutes]).to be_present
    end

    it "validates amount_cents is >= 0" do
      req = build(:request, amount_cents: -1)
      expect(req).not_to be_valid

      req.amount_cents = 0
      expect(req).to be_valid
    end

    context "when canceled" do
      it "requires cancel_reason" do
        req = build(:request, :canceled, cancel_reason: nil)
        expect(req).not_to be_valid
        expect(req.errors[:cancel_reason]).to be_present
      end
    end

    context "when rejected" do
      it "requires reject_reason" do
        req = build(:request, :rejected, reject_reason: nil)
        expect(req).not_to be_valid
        expect(req.errors[:reject_reason]).to be_present
      end
    end
  end

  describe "state machine" do
    let(:req) { create(:request) }

    it "has initial state of created" do
      expect(req.state).to eq("created")
      expect(req).to be_created
    end

    describe "accept event" do
      it "transitions from created to accepted" do
        req.accept!
        expect(req).to be_accepted
      end

      it "cannot accept from other states" do
        req.accept!
        expect { req.accept! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "decline event" do
      it "transitions from created to declined" do
        req.decline!
        expect(req).to be_declined
      end

      it "cannot decline from accepted" do
        req.accept!
        expect { req.decline! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "miss event" do
      it "transitions from created to missed" do
        req.miss!
        expect(req).to be_missed
      end

      it "cannot miss from accepted" do
        req.accept!
        expect { req.miss! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "start event" do
      it "transitions from accepted to started" do
        req.accept!
        req.start!
        expect(req).to be_started
      end

      it "transitions from created_accepted to started" do
        ca_req = create(:request, :created_accepted)
        ca_req.start!
        expect(ca_req).to be_started
      end

      it "sets started_at timestamp" do
        req.accept!
        freeze_time do
          req.start!
          expect(req.reload.started_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "fulfill event" do
      before { req.accept!; req.start! }

      it "transitions from started to fulfilled" do
        req.fulfill!
        expect(req).to be_fulfilled
      end

      it "sets completed_at timestamp" do
        freeze_time do
          req.fulfill!
          expect(req.reload.completed_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "cancel event" do
      it "transitions from created to canceled" do
        req.update!(cancel_reason: "Changed my mind")
        req.cancel!
        expect(req).to be_canceled
      end

      it "transitions from accepted to canceled" do
        req.accept!
        req.update!(cancel_reason: "Changed my mind")
        req.cancel!
        expect(req).to be_canceled
      end

      it "transitions from created_accepted to canceled" do
        ca_req = create(:request, :created_accepted)
        ca_req.update!(cancel_reason: "Changed my mind")
        ca_req.cancel!
        expect(ca_req).to be_canceled
      end

      it "cannot cancel from started" do
        req.accept!
        req.start!
        expect { req.cancel! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "reject event" do
      it "transitions from accepted to rejected" do
        req.accept!
        req.update!(reject_reason: "Cannot make it")
        req.reject!
        expect(req).to be_rejected
      end

      it "transitions from created_accepted to rejected" do
        ca_req = create(:request, :created_accepted)
        ca_req.update!(reject_reason: "Cannot make it")
        ca_req.reject!
        expect(ca_req).to be_rejected
      end

      it "transitions from started to rejected" do
        req.accept!
        req.start!
        req.update!(reject_reason: "Emergency")
        req.reject!
        expect(req).to be_rejected
      end

      it "cannot reject from created" do
        expect { req.reject! }.to raise_error(AASM::InvalidTransition)
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
