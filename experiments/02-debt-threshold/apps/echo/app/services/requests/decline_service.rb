module Requests
  class DeclineService
    def initialize(request:, provider:, reason:)
      @request = request
      @provider = provider
      @reason = reason
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id
      return error("Decline reason is required") if @reason.blank?

      @request.decline_reason = @reason
      @request.decline!

      NotificationService.notify(@request.client, :request_declined, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot decline request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
