module Announcements
  class PublishService
    def initialize(announcement:, client:)
      @announcement = announcement
      @client = client
    end

    def call
      return error("Not your announcement") unless @announcement.client_id == @client.id

      @announcement.publish!
      { success: true, announcement: @announcement }
    rescue AASM::InvalidTransition
      error("Cannot publish announcement in #{@announcement.state} state")
    end

    private

    def error(message)
      { success: false, error: message }
    end
  end
end
