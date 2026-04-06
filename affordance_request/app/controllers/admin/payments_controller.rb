module Admin
  class PaymentsController < BaseController
    def index
      scope = Payment.includes(request: [:client, :provider])
      scope = scope.by_status(params[:status])
      scope = scope.order(created_at: :desc)
      @payments = paginate(scope)
      @total_count = scope.count
    end

    def show
      @payment = Payment.includes(request: [:client, :provider]).find(params[:id])
    end
  end
end
