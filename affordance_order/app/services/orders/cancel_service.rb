module Orders
  class CancelService
    def initialize(order:, client:, reason:)
      @order = order
      @client = client
      @reason = reason
    end

    def call
      return error("Not your order") unless @order.client_id == @client.id
      return error("Cancel reason is required") if @reason.blank?

      @order.cancel_reason = @reason
      @order.cancel!

      if @order.payment && %w[held charged].include?(@order.payment.status)
        PaymentGateway.refund(@order.payment)
      end

      NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot cancel order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
