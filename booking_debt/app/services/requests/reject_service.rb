module Requests
  class RejectService
    def initialize(request:, provider:, reason:)
      @request = request
      @provider = provider
      @reason = reason
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id
      return error("Reject reason is required") if @reason.blank?

      @request.reject_reason = @reason
      @request.reject!

      if @request.payment && %w[held charged].include?(@request.payment.status)
        PaymentGateway.refund(@request.payment)
      end

      NotificationService.notify(@request.client, :request_rejected, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot reject request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
