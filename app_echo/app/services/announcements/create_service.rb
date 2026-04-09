module Announcements
  class CreateService
    def initialize(client:, params:)
      @client = client
      @params = params
    end

    def call
      announcement = Announcement.new(
        client: @client,
        title: @params[:title],
        description: @params[:description],
        location: @params[:location],
        scheduled_at: @params[:scheduled_at],
        duration_minutes: @params[:duration_minutes],
        budget_cents: @params[:budget_cents],
        currency: @params[:currency] || "RUB"
      )

      announcement.save!
      { success: true, announcement: announcement }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, errors: e.record.errors }
    end
  end
end
