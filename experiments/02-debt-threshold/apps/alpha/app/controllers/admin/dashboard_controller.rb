module Admin
  class DashboardController < BaseController
    def index
      @clients_count = Client.count
      @providers_count = Provider.count

      @requests_by_state = Request.group(:state).count
      @recent_requests = Request.includes(:client, :provider).order(created_at: :desc).limit(10)
    end
  end
end
