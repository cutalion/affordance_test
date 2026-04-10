class PaymentHoldJob < ApplicationJob
  queue_as :default

  def perform
    requests = Request.where(state: %w[pending confirmed])
                  .where("scheduled_at BETWEEN ? AND ?", Time.current, 1.day.from_now)
                  .includes(:payment, client: :cards)

    requests.find_each do |request|
      next unless request.payment&.status == "pending"
      result = PaymentGateway.hold(request.payment)
      Rails.logger.info "[PaymentHoldJob] request_id=#{request.id} success=#{result[:success]} error=#{result[:error]}"
    end
  end
end
