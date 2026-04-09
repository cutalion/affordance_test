Rails.application.config.admin_username = ENV.fetch("ADMIN_USERNAME", "admin")
Rails.application.config.admin_password = ENV.fetch("ADMIN_PASSWORD", "admin_password")
