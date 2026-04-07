class RequestMailer < ApplicationMailer
  def request_created(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "New request ##{@request_id}")
  end

  def request_confirmed(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} confirmed")
  end

  def request_started(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} started")
  end

  def request_completed(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} completed")
  end

  def request_canceled(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} canceled")
  end

  def request_rejected(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} rejected")
  end

  def review_reminder(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Leave a review for request ##{@request_id}")
  end
end
