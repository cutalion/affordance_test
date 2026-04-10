module Responses
  class RejectService
    def initialize(response:, client:)
      @response = response
      @client = client
    end

    def call
      return error("Not your announcement") unless @response.announcement.client_id == @client.id

      @response.reject!
      NotificationService.notify(@response.provider, :response_rejected, announcement_id: @response.announcement_id)
      { success: true, response: @response }
    rescue AASM::InvalidTransition
      error("Cannot reject response in #{@response.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
