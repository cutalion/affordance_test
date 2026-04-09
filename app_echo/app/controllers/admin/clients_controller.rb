module Admin
  class ClientsController < BaseController
    def index
      @clients = paginate(Client.order(created_at: :desc))
      @total_count = Client.count
    end

    def show
      @client = Client.find(params[:id])
    end
  end
end
