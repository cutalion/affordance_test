class Provider < ApplicationRecord
  serialize :notification_preferences, coder: JSON

  has_many :requests, dependent: :destroy
  has_many :reviews, as: :author, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :api_token, presence: true, uniqueness: true
  validates :rating, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5 }

  before_validation :generate_api_token, on: :create

  scope :active, -> { where(active: true) }

  private

  def generate_api_token
    self.api_token ||= SecureRandom.hex(32)
  end
end
