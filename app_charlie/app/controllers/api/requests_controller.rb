module Api
  class RequestsController < BaseController
    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]

    def index
      requests = scoped_requests
      requests = requests.by_state(params[:state]) if params[:state].present?
      requests = requests.scheduled_between(params[:from], params[:to])
      requests = requests.sorted.page(params[:page])
      render json: requests.map { |r| request_summary_json(r) }
    end

    def show
      render json: request_detail_json(@request)
    end

    def create
      client = current_client!
      return if performed?

      provider = Provider.find_by(id: params[:provider_id])
      return render_not_found unless provider

      result = Requests::CreateService.new(
        client: client,
        provider: provider,
        params: request_params
      ).call

      if result[:success]
        render json: request_detail_json(result[:request]), status: :created
      else
        render_unprocessable(result[:errors].full_messages)
      end
    end

    def accept
      provider = current_provider!
      return if performed?

      result = Requests::AcceptService.new(request: @request, provider: provider).call
      handle_service_result(result)
    end

    def decline
      provider = current_provider!
      return if performed?

      if params[:reason].blank?
        return render_unprocessable(["Reason is required"])
      end

      result = Requests::DeclineService.new(
        request: @request,
        provider: provider,
        reason: params[:reason]
      ).call
      handle_service_result(result)
    end

    def start
      provider = current_provider!
      return if performed?

      result = Requests::StartService.new(request: @request, provider: provider).call
      handle_service_result(result)
    end

    def complete
      provider = current_provider!
      return if performed?

      result = Requests::CompleteService.new(request: @request, provider: provider).call
      handle_service_result(result)
    end

    def cancel
      client = current_client!
      return if performed?

      if params[:reason].blank?
        return render_unprocessable(["Reason is required"])
      end

      result = Requests::CancelService.new(
        request: @request,
        client: client,
        reason: params[:reason]
      ).call
      handle_service_result(result)
    end

    def reject
      provider = current_provider!
      return if performed?

      if params[:reason].blank?
        return render_unprocessable(["Reason is required"])
      end

      result = Requests::RejectService.new(
        request: @request,
        provider: provider,
        reason: params[:reason]
      ).call
      handle_service_result(result)
    end

    private

    def set_request
      @request = Request.find_by(id: params[:id])
      render_not_found unless @request
    end

    def scoped_requests
      if current_user.is_a?(Client)
        Request.where(client: current_user)
      else
        Request.where(provider: current_user)
      end
    end

    def request_params
      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
    end

    def handle_service_result(result)
      if result[:success]
        render json: request_detail_json(result[:request])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def request_summary_json(request)
      {
        id: request.id,
        state: request.state,
        scheduled_at: request.scheduled_at,
        amount_cents: request.amount_cents,
        currency: request.currency,
        client_id: request.client_id,
        provider_id: request.provider_id
      }
    end

    def request_detail_json(request)
      {
        id: request.id,
        state: request.state,
        scheduled_at: request.scheduled_at,
        duration_minutes: request.duration_minutes,
        location: request.location,
        notes: request.notes,
        amount_cents: request.amount_cents,
        currency: request.currency,
        decline_reason: request.decline_reason,
        cancel_reason: request.cancel_reason,
        reject_reason: request.reject_reason,
        accepted_at: request.accepted_at,
        expired_at: request.expired_at,
        started_at: request.started_at,
        completed_at: request.completed_at,
        client_id: request.client_id,
        provider_id: request.provider_id,
        payment: request.payment ? {
          id: request.payment.id,
          status: request.payment.status,
          amount_cents: request.payment.amount_cents,
          currency: request.payment.currency
        } : nil,
        created_at: request.created_at,
        updated_at: request.updated_at
      }
    end
  end
end
