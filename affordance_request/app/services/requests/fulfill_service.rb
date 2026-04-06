module Requests
  class FulfillService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      @request.fulfill!

      if @request.payment&.status == "held"
        PaymentGateway.charge(@request.payment)
      end

      NotificationService.notify(@request.client, :request_fulfilled, request_id: @request.id)
      NotificationService.notify(@request.provider, :request_fulfilled, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot fulfill request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
