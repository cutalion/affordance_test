require "rails_helper"

RSpec.describe Response, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:announcement) }
    it { is_expected.to belong_to(:provider) }
  end

  describe "validations" do
    subject { build(:response) }

    it "validates uniqueness of provider per announcement" do
      announcement = create(:announcement, :published)
      provider = create(:provider)
      create(:response, announcement: announcement, provider: provider)

      duplicate = build(:response, announcement: announcement, provider: provider)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:announcement_id]).to include("already responded")
    end
  end

  describe "state machine" do
    let(:response) { create(:response) }

    it "has initial state of pending" do
      expect(response.state).to eq("pending")
      expect(response).to be_pending
    end

    describe "select event" do
      it "transitions from pending to selected" do
        response.select!
        expect(response).to be_selected
      end

      it "cannot select from rejected state" do
        response.reject!
        expect { response.select! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "reject event" do
      it "transitions from pending to rejected" do
        response.reject!
        expect(response).to be_rejected
      end

      it "cannot reject from selected state" do
        response.select!
        expect { response.reject! }.to raise_error(AASM::InvalidTransition)
      end
    end
  end
end
