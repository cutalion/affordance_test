class Request < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  belongs_to :provider
  belongs_to :announcement, optional: true
  has_one :payment, dependent: :destroy
  has_many :reviews, dependent: :destroy

  validates :scheduled_at, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :decline_reason, presence: true, if: -> { declined? }
  validates :cancel_reason, presence: true, if: -> { canceled? }
  validates :reject_reason, presence: true, if: -> { rejected? }

  scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
  scope :past, -> { where("scheduled_at <= ?", Time.current) }
  scope :by_state, ->(state) { where(state: state) if state.present? }
  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
  scope :scheduled_between, ->(from, to) {
    scope = all
    scope = scope.where("scheduled_at >= ?", from) if from.present?
    scope = scope.where("scheduled_at <= ?", to) if to.present?
    scope
  }
  scope :sorted, -> { order(scheduled_at: :desc) }

  aasm column: :state do
    state :pending, initial: true
    state :accepted
    state :in_progress
    state :completed
    state :declined
    state :expired
    state :canceled
    state :rejected

    event :accept do
      transitions from: :pending, to: :accepted
      after do
        update!(accepted_at: Time.current)
      end
    end

    event :decline do
      transitions from: :pending, to: :declined
    end

    event :expire do
      transitions from: :pending, to: :expired
      after do
        update!(expired_at: Time.current)
      end
    end

    event :start do
      transitions from: :accepted, to: :in_progress
      after do
        update!(started_at: Time.current)
      end
    end

    event :complete do
      transitions from: :in_progress, to: :completed
      after do
        update!(completed_at: Time.current)
      end
    end

    event :cancel do
      transitions from: [:pending, :accepted], to: :canceled
    end

    event :reject do
      transitions from: [:accepted, :in_progress], to: :rejected
    end
  end
end
