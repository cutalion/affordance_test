module Orders
  class RejectService
    def initialize(order:, provider:, reason:)
      @order = order
      @provider = provider
      @reason = reason
    end

    def call
      return error("Not your order") unless @order.provider_id == @provider.id
      return error("Reject reason is required") if @reason.blank?

      @order.reject_reason = @reason
      @order.reject!

      if @order.payment && %w[held charged].include?(@order.payment.status)
        PaymentGateway.refund(@order.payment)
      end

      NotificationService.notify(@order.client, :order_rejected, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot reject order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
