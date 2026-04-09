module Requests
  class CancelService
    def initialize(request:, client:, reason:)
      @request = request
      @client = client
      @reason = reason
    end

    def call
      return error("Not your request") unless @request.client_id == @client.id
      return error("Cancel reason is required") if @reason.blank?

      @request.cancel_reason = @reason
      @request.cancel!

      if @request.payment && %w[held charged].include?(@request.payment.status)
        PaymentGateway.refund(@request.payment)
      end

      NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot cancel request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
