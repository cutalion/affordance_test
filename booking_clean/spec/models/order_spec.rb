require "rails_helper"

RSpec.describe Order, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:request).optional }
    it { is_expected.to belong_to(:client) }
    it { is_expected.to belong_to(:provider) }
    it { is_expected.to have_one(:payment).dependent(:destroy) }
    it { is_expected.to have_many(:reviews).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:order) }

    it { is_expected.to validate_presence_of(:scheduled_at) }
    it { is_expected.to validate_presence_of(:duration_minutes) }
    it { is_expected.to validate_presence_of(:amount_cents) }
    it { is_expected.to validate_presence_of(:currency) }

    it "validates duration_minutes is greater than 0" do
      order = build(:order, duration_minutes: 0)
      expect(order).not_to be_valid
      expect(order.errors[:duration_minutes]).to be_present
    end

    it "validates amount_cents is >= 0" do
      order = build(:order, amount_cents: -1)
      expect(order).not_to be_valid

      order.amount_cents = 0
      expect(order).to be_valid
    end

    context "when canceled" do
      it "requires cancel_reason" do
        order = build(:order, :canceled, cancel_reason: nil)
        expect(order).not_to be_valid
        expect(order.errors[:cancel_reason]).to be_present
      end
    end

    context "when rejected" do
      it "requires reject_reason" do
        order = build(:order, :rejected, reject_reason: nil)
        expect(order).not_to be_valid
        expect(order.errors[:reject_reason]).to be_present
      end
    end
  end

  describe "state machine" do
    let(:order) { create(:order) }

    it "has initial state of pending" do
      expect(order.state).to eq("pending")
      expect(order).to be_pending
    end

    describe "confirm event" do
      it "transitions from pending to confirmed" do
        order.confirm!
        expect(order).to be_confirmed
      end

      it "cannot confirm from other states" do
        order.confirm!
        expect { order.confirm! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "start event" do
      before { order.confirm! }

      it "transitions from confirmed to in_progress" do
        order.start!
        expect(order).to be_in_progress
      end

      it "sets started_at timestamp" do
        freeze_time do
          order.start!
          expect(order.reload.started_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "complete event" do
      before { order.confirm!; order.start! }

      it "transitions from in_progress to completed" do
        order.complete!
        expect(order).to be_completed
      end

      it "sets completed_at timestamp" do
        freeze_time do
          order.complete!
          expect(order.reload.completed_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "cancel event" do
      it "transitions from pending to canceled" do
        order.update!(cancel_reason: "Changed my mind")
        order.cancel!
        expect(order).to be_canceled
      end

      it "transitions from confirmed to canceled" do
        order.confirm!
        order.update!(cancel_reason: "Changed my mind")
        order.cancel!
        expect(order).to be_canceled
      end

      it "cannot cancel from in_progress" do
        order.confirm!
        order.start!
        expect { order.cancel! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "reject event" do
      it "transitions from confirmed to rejected" do
        order.confirm!
        order.update!(reject_reason: "Cannot make it")
        order.reject!
        expect(order).to be_rejected
      end

      it "transitions from in_progress to rejected" do
        order.confirm!
        order.start!
        order.update!(reject_reason: "Emergency")
        order.reject!
        expect(order).to be_rejected
      end

      it "cannot reject from pending" do
        expect { order.reject! }.to raise_error(AASM::InvalidTransition)
      end
    end
  end

  describe "scopes" do
    let!(:future_order) { create(:order, scheduled_at: 1.day.from_now) }
    let!(:past_order) { create(:order, scheduled_at: 1.day.ago) }
    let!(:confirmed_order) { create(:order, :confirmed) }

    describe ".upcoming" do
      it "returns orders with scheduled_at in the future" do
        expect(Order.upcoming).to include(future_order)
        expect(Order.upcoming).not_to include(past_order)
      end
    end

    describe ".past" do
      it "returns orders with scheduled_at in the past" do
        expect(Order.past).to include(past_order)
        expect(Order.past).not_to include(future_order)
      end
    end

    describe ".by_state" do
      it "filters by state" do
        expect(Order.by_state("confirmed")).to include(confirmed_order)
        expect(Order.by_state("confirmed")).not_to include(future_order)
      end

      it "returns all when state is blank" do
        expect(Order.by_state(nil).count).to eq(Order.count)
      end
    end

    describe ".sorted" do
      it "returns orders sorted by scheduled_at descending" do
        sorted = Order.sorted.to_a
        expect(sorted.first.scheduled_at).to be >= sorted.last.scheduled_at
      end
    end
  end
end
