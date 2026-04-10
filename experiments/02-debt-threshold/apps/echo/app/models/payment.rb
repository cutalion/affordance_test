class Payment < ApplicationRecord
  belongs_to :request
  belongs_to :card, optional: true

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending held charged refunded] }

  scope :by_status, ->(status) { where(status: status) if status.present? }

  def hold!
    update!(status: "held", held_at: Time.current)
  end

  def charge!
    update!(status: "charged", charged_at: Time.current)
  end

  def refund!
    update!(status: "refunded", refunded_at: Time.current)
  end
end
