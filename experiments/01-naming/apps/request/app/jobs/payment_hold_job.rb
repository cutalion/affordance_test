class PaymentHoldJob < ApplicationJob
  queue_as :default

  def perform
    requests = Request.where(state: %w[created created_accepted accepted])
                  .where("scheduled_at BETWEEN ? AND ?", Time.current, 1.day.from_now)
                  .includes(:payment, client: :cards)

    requests.find_each do |req|
      next unless req.payment&.status == "pending"
      result = PaymentGateway.hold(req.payment)
      Rails.logger.info "[PaymentHoldJob] request_id=#{req.id} success=#{result[:success]} error=#{result[:error]}"
    end
  end
end
