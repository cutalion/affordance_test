class NotificationService
  LOG_PATH = -> { Rails.root.join("log/notifications.log") }

  def self.notify(recipient, event, payload = {})
    new(recipient, event, payload).deliver
  end

  def initialize(recipient, event, payload)
    @recipient = recipient
    @event = event
    @payload = payload
    @preferences = recipient.notification_preferences
  end

  def deliver
    send_push if @preferences["push"]
    send_sms if @preferences["sms"]
    send_email if @preferences["email"]
  end

  private

  def send_push
    log_notification("PUSH", "to=#{recipient_identifier} event=#{@event} #{payload_string}")
  end

  def send_sms
    log_notification("SMS", "to=#{@recipient.phone} event=#{@event} #{payload_string}")
  end

  def send_email
    mailer_class = Object.const_get("RequestMailer") rescue nil
    if mailer_class&.respond_to?(@event)
      mailer_class.public_send(@event, @recipient, @payload).deliver_later
    end
    log_notification("EMAIL", "to=#{@recipient.email} event=#{@event} #{payload_string}")
  end

  def recipient_identifier
    "#{@recipient.class.name.downcase}_#{@recipient.id}"
  end

  def payload_string
    @payload.map { |k, v| "#{k}=#{v}" }.join(" ")
  end

  def log_notification(channel, message)
    File.open(self.class::LOG_PATH.call, "a") do |f|
      f.puts "[#{channel}] #{message} at=#{Time.current.iso8601}"
    end
  end
end
