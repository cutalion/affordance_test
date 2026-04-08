module Api
  class OrdersController < BaseController
    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]

    def index
      orders = scoped_orders
      orders = orders.by_state(params[:state]) if params[:state].present?
      orders = orders.scheduled_between(params[:from], params[:to])
      orders = orders.sorted.page(params[:page])
      render json: orders.map { |o| order_summary_json(o) }
    end

    def show
      render json: order_detail_json(@order)
    end

    def create
      client = current_client!
      return if performed?

      provider = Provider.find_by(id: params[:provider_id])
      return render_not_found unless provider

      result = Orders::CreateService.new(
        client: client,
        provider: provider,
        params: order_params
      ).call

      if result[:success]
        render json: order_detail_json(result[:order]), status: :created
      else
        render_unprocessable(result[:errors].full_messages)
      end
    end

    def confirm
      provider = current_provider!
      return if performed?

      result = Orders::ConfirmService.new(order: @order, provider: provider).call
      handle_service_result(result)
    end

    def start
      provider = current_provider!
      return if performed?

      result = Orders::StartService.new(order: @order, provider: provider).call
      handle_service_result(result)
    end

    def complete
      provider = current_provider!
      return if performed?

      result = Orders::CompleteService.new(order: @order, provider: provider).call
      handle_service_result(result)
    end

    def cancel
      client = current_client!
      return if performed?

      if params[:reason].blank?
        return render_unprocessable(["Reason is required"])
      end

      result = Orders::CancelService.new(
        order: @order,
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

      result = Orders::RejectService.new(
        order: @order,
        provider: provider,
        reason: params[:reason]
      ).call
      handle_service_result(result)
    end

    private

    def set_order
      @order = Order.find_by(id: params[:id])
      render_not_found unless @order
    end

    def scoped_orders
      if current_user.is_a?(Client)
        Order.where(client: current_user)
      else
        Order.where(provider: current_user)
      end
    end

    def order_params
      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
    end

    def handle_service_result(result)
      if result[:success]
        render json: order_detail_json(result[:order])
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    end

    def order_summary_json(order)
      {
        id: order.id,
        state: order.state,
        scheduled_at: order.scheduled_at,
        amount_cents: order.amount_cents,
        currency: order.currency,
        client_id: order.client_id,
        provider_id: order.provider_id
      }
    end

    def order_detail_json(order)
      {
        id: order.id,
        state: order.state,
        scheduled_at: order.scheduled_at,
        duration_minutes: order.duration_minutes,
        location: order.location,
        notes: order.notes,
        amount_cents: order.amount_cents,
        currency: order.currency,
        cancel_reason: order.cancel_reason,
        reject_reason: order.reject_reason,
        started_at: order.started_at,
        completed_at: order.completed_at,
        client_id: order.client_id,
        provider_id: order.provider_id,
        payment: order.payment ? {
          id: order.payment.id,
          status: order.payment.status,
          amount_cents: order.payment.amount_cents,
          currency: order.payment.currency
        } : nil,
        created_at: order.created_at,
        updated_at: order.updated_at
      }
    end
  end
end
