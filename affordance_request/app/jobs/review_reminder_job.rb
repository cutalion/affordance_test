class ReviewReminderJob < ApplicationJob
  queue_as :default

  def perform
    requests = Request.where(state: "fulfilled")
                  .where("completed_at < ?", 24.hours.ago)
                  .where("completed_at > ?", 48.hours.ago)
                  .includes(:reviews, :client, :provider)

    requests.find_each do |req|
      remind_client(req) unless req.reviews.exists?(author: req.client)
      remind_provider(req) unless req.reviews.exists?(author: req.provider)
    end
  end

  private

  def remind_client(req)
    NotificationService.notify(req.client, :review_reminder, request_id: req.id)
  end

  def remind_provider(req)
    NotificationService.notify(req.provider, :review_reminder, request_id: req.id)
  end
end
