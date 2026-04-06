module AuthHelpers
  def auth_headers(user)
    { "Authorization" => "Bearer #{user.api_token}" }
  end

  def admin_auth_headers
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "admin_password")
    { "Authorization" => credentials }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
