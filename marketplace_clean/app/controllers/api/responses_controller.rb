module Api
  class ResponsesController < BaseController
    before_action :set_announcement, only: [:index, :create]
    before_action :set_response, only: [:select, :reject]

    def index
      responses = @announcement.responses
      responses = responses.where(state: params[:state]) if params[:state].present?
      render json: responses.map { |r| response_json(r) }
    end

    def create
      provider = current_provider!
      return if performed?

      result = Responses::CreateService.new(
        announcement: @announcement,
        provider: provider,
        params: response_params
      ).call

      if result[:success]
        render json: response_json(result[:response]), status: :created
      else
        if result[:errors]
          render_unprocessable(result[:errors].full_messages)
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      end
    end

    def select
      client = current_client!
      return if performed?

      result = Responses::SelectService.new(response: @response, client: client).call
      handle_service_result(result)
    end

    def reject
      client = current_client!
      return if performed?

      result = Responses::RejectService.new(response: @response, client: client).call
      handle_service_result(result)
    end

    private

    def set_announcement
      @announcement = Announcement.find_by(id: params[:announcement_id])
      render_not_found unless @announcement
    end

    def set_response
      @response = Response.find_by(id: params[:id])
      render_not_found unless @response
    end

    def response_params
      params.permit(:message, :proposed_amount_cents)
    end

    def handle_service_result(result)
      if result[:success]
        render json: response_json(result[:response])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def response_json(response)
      {
        id: response.id,
        announcement_id: response.announcement_id,
        provider_id: response.provider_id,
        message: response.message,
        proposed_amount_cents: response.proposed_amount_cents,
        state: response.state,
        created_at: response.created_at,
        updated_at: response.updated_at
      }
    end
  end
end
