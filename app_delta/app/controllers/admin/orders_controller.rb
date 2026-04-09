module Admin
  class OrdersController < BaseController
    def index
      scope = Order.includes(:client, :provider)
      scope = scope.by_state(params[:state])
      scope = scope.scheduled_between(params[:from], params[:to])
      scope = scope.by_client(params[:client_id]) if params[:client_id].present?
      scope = scope.by_provider(params[:provider_id]) if params[:provider_id].present?
      scope = scope.order(created_at: :desc)
      @orders = paginate(scope)
      @total_count = scope.count
    end

    def show
      @order = Order.includes(:client, :provider, :payment, :reviews).find(params[:id])
    end
  end
end
