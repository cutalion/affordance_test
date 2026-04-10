module Responses
  class SelectService
    def initialize(response:, client:)
      @response = response
      @client = client
      @announcement = response.announcement
    end

    def call
      return error("Not your announcement") unless @announcement.client_id == @client.id

      Response.transaction do
        @response.select!

        # Reject all other pending responses
        @announcement.responses.where.not(id: @response.id).where(state: "pending").find_each do |r|
          r.reject!
        end

        # Create an order from the selected response
        Orders::CreateService.new(
          client: @announcement.client,
          provider: @response.provider,
          params: {
            scheduled_at: @announcement.scheduled_at || 3.days.from_now,
            duration_minutes: @announcement.duration_minutes || 120,
            location: @announcement.location,
            notes: "From announcement: #{@announcement.title}",
            amount_cents: @response.proposed_amount_cents || @announcement.budget_cents || 0,
            currency: @announcement.currency
          }
        ).call

        @announcement.close!
      end

      NotificationService.notify(@response.provider, :response_selected, announcement_id: @announcement.id)
      { success: true, response: @response }
    rescue AASM::InvalidTransition
      error("Cannot select response in #{@response.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
