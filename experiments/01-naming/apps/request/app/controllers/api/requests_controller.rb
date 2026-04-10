module Api
  class RequestsController < BaseController
    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]

    def index
      requests = scoped_requests
      requests = requests.by_state(params[:state]) if params[:state].present?
      requests = requests.scheduled_between(params[:from], params[:to])
      requests = requests.sorted.page(params[:page])
      render json: requests.map { |r| request_summary_json(r) }
    end

    def show
      render json: request_detail_json(@the_request)
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

    def create_direct
      provider = current_provider!
      return if performed?

      client = Client.find_by(id: params[:client_id])
      return render_not_found unless client

      result = Requests::CreateAcceptedService.new(
        provider: provider,
        client: client,
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

      result = Requests::AcceptService.new(request: @the_request, provider: provider).call
      handle_service_result(result)
    end

    def decline
      provider = current_provider!
      return if performed?

      result = Requests::DeclineService.new(request: @the_request, provider: provider).call
      handle_service_result(result)
    end

    def start
      provider = current_provider!
      return if performed?

      result = Requests::StartService.new(request: @the_request, provider: provider).call
      handle_service_result(result)
    end

    def fulfill
      provider = current_provider!
      return if performed?

      result = Requests::FulfillService.new(request: @the_request, provider: provider).call
      handle_service_result(result)
    end

    def cancel
      client = current_client!
      return if performed?

      if params[:reason].blank?
        return render_unprocessable(["Reason is required"])
      end

      result = Requests::CancelService.new(
        request: @the_request,
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
        request: @the_request,
        provider: provider,
        reason: params[:reason]
      ).call
      handle_service_result(result)
    end

    private

    def set_request
      @the_request = Request.find_by(id: params[:id])
      render_not_found unless @the_request
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

    def request_summary_json(req)
      {
        id: req.id,
        state: req.state,
        scheduled_at: req.scheduled_at,
        amount_cents: req.amount_cents,
        currency: req.currency,
        client_id: req.client_id,
        provider_id: req.provider_id
      }
    end

    def request_detail_json(req)
      {
        id: req.id,
        state: req.state,
        scheduled_at: req.scheduled_at,
        duration_minutes: req.duration_minutes,
        location: req.location,
        notes: req.notes,
        amount_cents: req.amount_cents,
        currency: req.currency,
        cancel_reason: req.cancel_reason,
        reject_reason: req.reject_reason,
        started_at: req.started_at,
        completed_at: req.completed_at,
        client_id: req.client_id,
        provider_id: req.provider_id,
        payment: req.payment ? {
          id: req.payment.id,
          status: req.payment.status,
          amount_cents: req.payment.amount_cents,
          currency: req.payment.currency
        } : nil,
        created_at: req.created_at,
        updated_at: req.updated_at
      }
    end
  end
end
