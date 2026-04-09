module Api
  class ReviewsController < BaseController
    before_action :set_order

    def index
      render json: @order.reviews.map { |r| review_json(r) }
    end

    def create
      review = @order.reviews.new(review_params)
      review.author = current_user

      if review.save
        update_provider_rating if current_user.is_a?(Client)
        render json: review_json(review), status: :created
      else
        render_unprocessable(review.errors.full_messages)
      end
    end

    private

    def set_order
      @order = Order.find_by(id: params[:order_id])
      render_not_found unless @order
    end

    def review_params
      params.permit(:rating, :body)
    end

    def update_provider_rating
      provider = @order.provider
      avg = Review.joins(:order)
                  .where(orders: { provider_id: provider.id }, author_type: "Client")
                  .average(:rating)
      provider.update!(rating: avg.to_f.round(2)) if avg
    end

    def review_json(review)
      {
        id: review.id,
        order_id: review.order_id,
        rating: review.rating,
        body: review.body,
        author_type: review.author_type,
        author_id: review.author_id,
        created_at: review.created_at
      }
    end
  end
end
