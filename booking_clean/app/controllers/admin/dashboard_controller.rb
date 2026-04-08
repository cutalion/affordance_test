module Admin
  class DashboardController < BaseController
    def index
      @clients_count = Client.count
      @providers_count = Provider.count

      @requests_by_state = Request.group(:state).count
      @orders_by_state = Order.group(:state).count
      @recent_requests = Request.includes(:client, :provider).order(created_at: :desc).limit(10)
      @recent_orders = Order.includes(:client, :provider).order(created_at: :desc).limit(10)
    end
  end
end
