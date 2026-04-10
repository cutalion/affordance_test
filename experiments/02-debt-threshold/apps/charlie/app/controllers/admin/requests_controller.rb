module Admin
  class RequestsController < BaseController
    def index
      scope = Request.includes(:client, :provider)
      scope = scope.by_state(params[:state])
      scope = scope.scheduled_between(params[:from], params[:to])
      scope = scope.by_client(params[:client_id]) if params[:client_id].present?
      scope = scope.by_provider(params[:provider_id]) if params[:provider_id].present?
      scope = scope.order(created_at: :desc)
      @requests = paginate(scope)
      @total_count = scope.count
    end

    def show
      @request = Request.includes(:client, :provider).find(params[:id])
    end
  end
end
