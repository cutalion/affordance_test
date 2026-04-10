module Requests
  class AcceptService
    def initialize(request:, actor:)
      @request = request
      @actor = actor
    end

    def call
      if @request.announcement.present?
        # Announcement response flow: client selects a provider's response
        return error("Not your announcement") unless @request.announcement.client_id == @actor.id
        accept_announcement_response!
      else
        # Direct invitation flow: provider accepts client's request
        return error("Not your request") unless @request.provider_id == @actor.id
        accept_invitation!
      end
    rescue AASM::InvalidTransition
      error("Cannot accept request in #{@request.state} state")
    end

    private

    def accept_invitation!
      Request.transaction do
        @request.accept!

        Payment.create!(
          request: @request,
          amount_cents: @request.amount_cents,
          currency: @request.currency,
          fee_cents: calculate_fee(@request.amount_cents),
          status: "pending"
        )
      end

      PaymentGateway.hold(@request.payment) if @request.client.default_card

      NotificationService.notify(@request.client, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    end

    def accept_announcement_response!
      Request.transaction do
        @request.accept!

        amount = @request.proposed_amount_cents || @request.announcement.budget_cents || 0
        Payment.create!(
          request: @request,
          amount_cents: amount,
          currency: @request.currency,
          fee_cents: calculate_fee(amount),
          status: "pending"
        )

        # Decline all other pending responses to this announcement
        @request.announcement.requests
          .where.not(id: @request.id)
          .where(state: "pending")
          .find_each do |r|
            r.decline_reason = "Another provider was selected"
            r.decline!
          end

        @request.announcement.close!
      end

      PaymentGateway.hold(@request.payment) if @request.client.default_card

      NotificationService.notify(@request.provider, :request_accepted, request_id: @request.id)
      { success: true, request: @request }
    end

    def calculate_fee(amount_cents)
      (amount_cents * 0.1).to_i
    end

    def error(message)
      { success: false, error: message }
    end
  end
end
