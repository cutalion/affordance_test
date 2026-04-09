module Api
  class BaseController < ApplicationController
    before_action :authenticate!

    private

    def authenticate!
      token = extract_bearer_token
      return render_unauthorized unless token

      @current_user = Client.find_by(api_token: token) || Provider.find_by(api_token: token)
      render_unauthorized unless @current_user
    end

    def extract_bearer_token
      header = request.headers["Authorization"]
      return nil unless header&.start_with?("Bearer ")
      header.sub("Bearer ", "").strip
    end

    def current_user
      @current_user
    end

    def current_client!
      return current_user if current_user.is_a?(Client)
      render_forbidden
    end

    def current_provider!
      return current_user if current_user.is_a?(Provider)
      render_forbidden
    end

    def render_unauthorized
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def render_forbidden
      render json: { error: "Forbidden" }, status: :forbidden
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end

    def render_unprocessable(errors)
      render json: { errors: errors }, status: :unprocessable_entity
    end
  end
end
