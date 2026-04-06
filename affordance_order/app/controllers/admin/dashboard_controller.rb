module Admin
  class DashboardController < BaseController
    def index
      @clients_count = Client.count
      @providers_count = Provider.count
      @total_revenue_cents = Order.where(state: "completed").sum(:amount_cents)
      @total_fees_cents = Payment.where(status: "charged").sum(:fee_cents)

      @orders_by_state = Order.group(:state).count
      @recent_orders = Order.includes(:client, :provider).order(created_at: :desc).limit(10)
    end
  end
end
