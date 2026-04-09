module Admin
  class ProvidersController < BaseController
    def index
      @providers = paginate(Provider.order(created_at: :desc))
      @total_count = Provider.count
    end

    def show
      @provider = Provider.find(params[:id])
    end
  end
end
