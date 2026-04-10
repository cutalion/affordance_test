class RequestMailer < ApplicationMailer
  def request_created(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "New request ##{@request_id}")
  end

  def request_created_accepted(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} created and accepted")
  end

  def request_accepted(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} accepted")
  end

  def request_declined(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} declined")
  end

  def request_started(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} started")
  end

  def request_fulfilled(recipient, payload)
    @recipient = recipient
    @request_id = payload[:request_id]
    mail(to: recipient.email, subject: "Request ##{@request_id} fulfilled")
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
