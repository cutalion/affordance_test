module NotificationHelpers
  def notification_log_path
    Rails.root.join("log/notifications.log")
  end

  def payment_log_path
    Rails.root.join("log/payments.log")
  end

  def read_notification_log
    File.exist?(notification_log_path) ? File.read(notification_log_path) : ""
  end

  def read_payment_log
    File.exist?(payment_log_path) ? File.read(payment_log_path) : ""
  end

  def clear_notification_log
    File.write(notification_log_path, "") if File.exist?(notification_log_path)
  end

  def clear_payment_log
    File.write(payment_log_path, "") if File.exist?(payment_log_path)
  end
end

RSpec.configure do |config|
  config.include NotificationHelpers

  config.before(:each) do
    clear_notification_log
    clear_payment_log
  end
end
