class ReviewReminderJob < ApplicationJob
  queue_as :default

  def perform
    requests = Request.where(state: "completed")
                  .where("completed_at < ?", 24.hours.ago)
                  .where("completed_at > ?", 48.hours.ago)
                  .includes(:reviews, :client, :provider)

    requests.find_each do |request|
      remind_client(request) unless request.reviews.exists?(author: request.client)
      remind_provider(request) unless request.reviews.exists?(author: request.provider)
    end
  end

  private

  def remind_client(request)
    NotificationService.notify(request.client, :review_reminder, request_id: request.id)
  end

  def remind_provider(request)
    NotificationService.notify(request.provider, :review_reminder, request_id: request.id)
  end
end
