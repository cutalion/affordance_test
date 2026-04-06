module Orders
  class CompleteService
    def initialize(order:, provider:)
      @order = order
      @provider = provider
    end

    def call
      return error("Not your order") unless @order.provider_id == @provider.id

      @order.complete!

      if @order.payment&.status == "held"
        PaymentGateway.charge(@order.payment)
      end

      NotificationService.notify(@order.client, :order_completed, order_id: @order.id)
      NotificationService.notify(@order.provider, :order_completed, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot complete order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
