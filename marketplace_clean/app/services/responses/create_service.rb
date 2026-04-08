module Responses
  class CreateService
    def initialize(announcement:, provider:, params:)
      @announcement = announcement
      @provider = provider
      @params = params
    end

    def call
      return error("Announcement not published") unless @announcement.published?

      response = @announcement.responses.new(
        provider: @provider,
        message: @params[:message],
        proposed_amount_cents: @params[:proposed_amount_cents]
      )

      response.save!
      NotificationService.notify(@announcement.client, :response_received, announcement_id: @announcement.id)
      { success: true, response: response }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
