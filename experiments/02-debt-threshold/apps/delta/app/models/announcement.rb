class Announcement < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  has_many :responses, dependent: :destroy

  validates :title, presence: true
  validates :currency, presence: true

  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :sorted, -> { order(created_at: :desc) }

  aasm column: :state do
    state :draft, initial: true
    state :published
    state :closed

    event :publish do
      transitions from: :draft, to: :published
      after do
        update!(published_at: Time.current)
      end
    end

    event :close do
      transitions from: :published, to: :closed
      after do
        update!(closed_at: Time.current)
      end
    end
  end
end
