module Requests
  class CreateAcceptedService
    def initialize(provider:, client:, params:)
      @provider = provider
      @client = client
      @params = params
    end

    def call
      request = Request.new(
        client: @client,
        provider: @provider,
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        location: @params[:location],
        notes: @params[:notes],
        amount_cents: @params[:amount_cents],
        currency: @params[:currency] || "RUB",
        state: "created_accepted"
      )

      Request.transaction do
        request.save!
        Payment.create!(
          request: request,
          amount_cents: request.amount_cents,
          currency: request.currency,
          fee_cents: calculate_fee(request.amount_cents),
          status: "pending"
        )
      end

      NotificationService.notify(@client, :request_created_accepted, request_id: request.id)
      { success: true, request: request }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end

    private

    def calculate_fee(amount_cents)
      (amount_cents * 0.1).to_i
    end
  end
end
