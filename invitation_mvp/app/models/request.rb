class Request < ApplicationRecord
  include AASM
  include Paginatable

  belongs_to :client
  belongs_to :provider

  validates :scheduled_at, presence: true
  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
  validates :decline_reason, presence: true, if: -> { declined? }

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
    state :declined
    state :expired

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
  end
end
