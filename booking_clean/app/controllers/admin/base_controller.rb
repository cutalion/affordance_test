module Admin
  class BaseController < ActionController::Base
    http_basic_authenticate_with(
      name: Rails.application.config.admin_username,
      password: Rails.application.config.admin_password
    )
    layout "admin"

    private

    def page_param
      [params[:page].to_i, 1].max
    end

    def per_page
      25
    end

    def paginate(scope)
      scope.offset((page_param - 1) * per_page).limit(per_page)
    end
  end
end
