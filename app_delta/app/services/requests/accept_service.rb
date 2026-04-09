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

        order_result = Orders::CreateService.new(
          client: @request.client,
          provider: @request.provider,
          params: {
            scheduled_at: @request.scheduled_at,
            duration_minutes: @request.duration_minutes,
            location: @request.location,
            notes: @request.notes,
            amount_cents: 350_000,
            currency: "RUB"
          },
          request: @request
        ).call

        unless order_result[:success]
          raise ActiveRecord::Rollback
          return error("Failed to create order")
        end
      end

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
