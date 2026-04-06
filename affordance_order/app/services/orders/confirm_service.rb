module Orders
  class ConfirmService
    def initialize(order:, provider:)
      @order = order
      @provider = provider
    end

    def call
      return error("Not your order") unless @order.provider_id == @provider.id

      @order.confirm!
      NotificationService.notify(@order.client, :order_confirmed, order_id: @order.id)
      { success: true, order: @order }
    rescue AASM::InvalidTransition
      error("Cannot confirm order in #{@order.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
