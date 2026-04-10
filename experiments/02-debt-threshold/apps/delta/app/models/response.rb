class Response < ApplicationRecord
  include AASM

  belongs_to :announcement
  belongs_to :provider

  validates :announcement_id, uniqueness: { scope: :provider_id, message: "already responded" }

  aasm column: :state do
    state :pending, initial: true
    state :selected
    state :rejected

    event :select do
      transitions from: :pending, to: :selected
    end

    event :reject do
      transitions from: :pending, to: :rejected
    end
  end
end
