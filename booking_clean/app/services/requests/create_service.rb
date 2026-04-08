module Requests
  class CreateService
    def initialize(client:, provider:, params:)
      @client = client
      @provider = provider
      @params = params
    end

    def call
      request = Request.new(
        client: @client,
        provider: @provider,
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        location: @params[:location],
        notes: @params[:notes]
      )

      request.save!

      NotificationService.notify(@provider, :request_created, request_id: request.id)
      { success: true, request: request }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end
  end
end
