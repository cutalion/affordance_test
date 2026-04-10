class Review < ApplicationRecord
  belongs_to :request
  belongs_to :author, polymorphic: true

  validates :rating, presence: true, numericality: { in: 1..5 }
  validates :author_type, inclusion: { in: %w[Client Provider] }
  validates :request_id, uniqueness: { scope: [:author_type, :author_id], message: "already reviewed by this author" }
  validate :request_must_be_fulfilled

  private

  def request_must_be_fulfilled
    return if self.request.nil?
    unless self.request.fulfilled?
      errors.add(:request, "must be fulfilled before reviewing")
    end
  end
end
