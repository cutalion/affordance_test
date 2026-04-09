module Api
  class CardsController < BaseController
    before_action :require_client!
    before_action :set_card, only: [:destroy, :set_default]

    def index
      render json: current_user.cards.map { |c| card_json(c) }
    end

    def create
      is_first = current_user.cards.empty?
      card = current_user.cards.new(card_params)
      card.default = is_first if is_first

      if card.save
        render json: card_json(card), status: :created
      else
        render_unprocessable(card.errors.full_messages)
      end
    end

    def destroy
      @card.destroy
      head :no_content
    end

    def set_default
      @card.make_default!
      render json: card_json(@card)
    end

    private

    def require_client!
      render_forbidden unless current_user.is_a?(Client)
    end

    def set_card
      @card = current_user.cards.find_by(id: params[:id])
      render_not_found unless @card
    end

    def card_params
      params.permit(:token, :last_four, :brand, :exp_month, :exp_year, :default)
    end

    def card_json(card)
      {
        id: card.id,
        brand: card.brand,
        last_four: card.last_four,
        exp_month: card.exp_month,
        exp_year: card.exp_year,
        default: card.default
      }
    end
  end
end
