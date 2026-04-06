class ReviewReminderJob < ApplicationJob
  queue_as :default

  def perform
    orders = Order.where(state: "completed")
                  .where("completed_at < ?", 24.hours.ago)
                  .where("completed_at > ?", 48.hours.ago)
                  .includes(:reviews, :client, :provider)

    orders.find_each do |order|
      remind_client(order) unless order.reviews.exists?(author: order.client)
      remind_provider(order) unless order.reviews.exists?(author: order.provider)
    end
  end

  private

  def remind_client(order)
    NotificationService.notify(order.client, :review_reminder, order_id: order.id)
  end

  def remind_provider(order)
    NotificationService.notify(order.provider, :review_reminder, order_id: order.id)
  end
end
