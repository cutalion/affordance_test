class Review < ApplicationRecord
  belongs_to :order
  belongs_to :author, polymorphic: true

  validates :rating, presence: true, numericality: { in: 1..5 }
  validates :author_type, inclusion: { in: %w[Client Provider] }
  validates :order_id, uniqueness: { scope: [:author_type, :author_id], message: "already reviewed by this author" }
  validate :order_must_be_completed

  private

  def order_must_be_completed
    return if order.nil?
    unless order.completed?
      errors.add(:order, "must be completed before reviewing")
    end
  end
end
