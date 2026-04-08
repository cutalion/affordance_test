module Requests
  class AcceptService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      Request.transaction do
        @request.accept!

        Payment.create!(
          request: @request,
          amount_cents: @request.amount_cents,
          currency: @request.currency,
          fee_cents: calculate_fee(@request.amount_cents),
          status: "pending"
        )
      end

      PaymentGateway.hold(@request.payment) if @request.client.default_card

      NotificationService.notify(@request.client, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot accept request in #{@request.state} state")
    end

    private

    def calculate_fee(amount_cents)
      (amount_cents * 0.1).to_i
    end

    def error(message)
      { success: false, error: message }
    end
  end
end
