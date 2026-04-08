module Api
  class PaymentsController < BaseController
    def index
      payments = scoped_payments
      payments = payments.by_status(params[:status]) if params[:status].present?
      render json: payments.map { |p| payment_json(p) }
    end

    def show
      payment = Payment.find_by(id: params[:id])
      return render_not_found unless payment

      unless authorized_for_payment?(payment)
        return render_forbidden
      end

      render json: payment_json(payment)
    end

    private

    def scoped_payments
      if current_user.is_a?(Client)
        Payment.joins(:order).where(orders: { client_id: current_user.id })
      else
        Payment.joins(:order).where(orders: { provider_id: current_user.id })
      end
    end

    def authorized_for_payment?(payment)
      if current_user.is_a?(Client)
        payment.order.client_id == current_user.id
      else
        payment.order.provider_id == current_user.id
      end
    end

    def payment_json(payment)
      {
        id: payment.id,
        order_id: payment.order_id,
        amount_cents: payment.amount_cents,
        currency: payment.currency,
        fee_cents: payment.fee_cents,
        status: payment.status,
        held_at: payment.held_at,
        charged_at: payment.charged_at,
        refunded_at: payment.refunded_at
      }
    end
  end
end
