class Card < ApplicationRecord
  belongs_to :client

  validates :token, presence: true
  validates :last_four, presence: true, length: { is: 4 }
  validates :brand, presence: true, inclusion: { in: %w[visa mastercard amex mir] }
  validates :exp_month, presence: true, numericality: { in: 1..12 }
  validates :exp_year, presence: true, numericality: { greater_than_or_equal_to: 2024 }

  after_save :ensure_single_default

  def make_default!
    transaction do
      client.cards.where.not(id: id).update_all(default: false)
      update!(default: true)
    end
  end

  private

  def ensure_single_default
    if default? && client.cards.where(default: true).where.not(id: id).exists?
      client.cards.where(default: true).where.not(id: id).update_all(default: false)
    end
  end
end
