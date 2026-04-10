class Request < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  belongs_to :provider
  has_one :payment, dependent: :destroy
  has_many :reviews, dependent: :destroy

  validates :scheduled_at, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
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
    state :created, initial: true
    state :created_accepted
    state :accepted
    state :started
    state :fulfilled
    state :declined
    state :missed
    state :canceled
    state :rejected

    event :accept do
      transitions from: :created, to: :accepted
    end

    event :decline do
      transitions from: :created, to: :declined
    end

    event :miss do
      transitions from: :created, to: :missed
    end

    event :start do
      transitions from: [:accepted, :created_accepted], to: :started
      after do
        update!(started_at: Time.current)
      end
    end

    event :fulfill do
      transitions from: :started, to: :fulfilled
      after do
        update!(completed_at: Time.current)
      end
    end

    event :cancel do
      transitions from: [:created, :accepted, :created_accepted], to: :canceled
    end

    event :reject do
      transitions from: [:accepted, :created_accepted, :started], to: :rejected
    end
  end
end
