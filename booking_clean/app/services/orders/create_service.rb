module Orders
  class CreateService
    def initialize(client:, provider:, params:, request: nil)
      @client = client
      @provider = provider
      @params = params
      @request = request
    end

    def call
      order = Order.new(
        request: @request,
        client: @client,
        provider: @provider,
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        location: @params[:location],
        notes: @params[:notes],
        amount_cents: @params[:amount_cents],
        currency: @params[:currency] || "RUB"
      )

      Order.transaction do
        order.save!
        Payment.create!(
          order: order,
          amount_cents: order.amount_cents,
          currency: order.currency,
          fee_cents: calculate_fee(order.amount_cents),
          status: "pending"
        )
      end

      NotificationService.notify(@provider, :order_created, order_id: order.id)
      { success: true, order: order }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end

    private

    def calculate_fee(amount_cents)
      (amount_cents * 0.1).to_i
    end
  end
end
