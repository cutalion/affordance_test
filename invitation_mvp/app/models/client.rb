class Client < ApplicationRecord
  serialize :notification_preferences, coder: JSON

  has_many :requests, dependent: :destroy
  has_many :cards, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :api_token, presence: true, uniqueness: true

  before_validation :generate_api_token, on: :create

  def default_card
    cards.find_by(default: true)
  end

  private

  def generate_api_token
    self.api_token ||= SecureRandom.hex(32)
  end
end
