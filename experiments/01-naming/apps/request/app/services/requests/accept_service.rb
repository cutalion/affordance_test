module Requests
  class AcceptService
    def initialize(request:, provider:)
      @request = request
      @provider = provider
    end

    def call
      return error("Not your request") unless @request.provider_id == @provider.id

      @request.accept!
      NotificationService.notify(@request.client, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    rescue AASM::InvalidTransition
      error("Cannot accept request in #{@request.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
