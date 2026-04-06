module Admin
  class ClientsController < BaseController
    def index
      @clients = paginate(Client.order(created_at: :desc))
      @total_count = Client.count
    end

    def show
      @client = Client.find(params[:id])
      @recent_orders = @client.orders.includes(:provider).order(created_at: :desc).limit(10)
      @cards = @client.cards.order(created_at: :desc)
    end
  end
end
