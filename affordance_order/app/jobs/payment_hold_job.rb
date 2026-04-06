class PaymentHoldJob < ApplicationJob
  queue_as :default

  def perform
    orders = Order.where(state: %w[pending confirmed])
                  .where("scheduled_at BETWEEN ? AND ?", Time.current, 1.day.from_now)
                  .includes(:payment, client: :cards)

    orders.find_each do |order|
      next unless order.payment&.status == "pending"
      result = PaymentGateway.hold(order.payment)
      Rails.logger.info "[PaymentHoldJob] order_id=#{order.id} success=#{result[:success]} error=#{result[:error]}"
    end
  end
end
