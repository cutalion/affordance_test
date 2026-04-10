class OrderMailer < ApplicationMailer
  def order_created(recipient, payload)
    @recipient = recipient
    @order_id = payload[:order_id]
    mail(to: recipient.email, subject: "New order ##{@order_id}")
  end

  def order_confirmed(recipient, payload)
    @recipient = recipient
    @order_id = payload[:order_id]
    mail(to: recipient.email, subject: "Order ##{@order_id} confirmed")
  end

  def order_started(recipient, payload)
    @recipient = recipient
    @order_id = payload[:order_id]
    mail(to: recipient.email, subject: "Order ##{@order_id} started")
  end

  def order_completed(recipient, payload)
    @recipient = recipient
    @order_id = payload[:order_id]
    mail(to: recipient.email, subject: "Order ##{@order_id} completed")
  end

  def order_canceled(recipient, payload)
    @recipient = recipient
    @order_id = payload[:order_id]
    mail(to: recipient.email, subject: "Order ##{@order_id} canceled")
  end

  def order_rejected(recipient, payload)
    @recipient = recipient
    @order_id = payload[:order_id]
    mail(to: recipient.email, subject: "Order ##{@order_id} rejected")
  end

  def review_reminder(recipient, payload)
    @recipient = recipient
    @order_id = payload[:order_id]
    mail(to: recipient.email, subject: "Leave a review for order ##{@order_id}")
  end
end
