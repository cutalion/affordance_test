module Api
  class ReviewsController < BaseController
    before_action :set_request

    def index
      render json: @request.reviews.map { |r| review_json(r) }
    end

    def create
      review = @request.reviews.new(review_params)
      review.author = current_user

      if review.save
        update_provider_rating if current_user.is_a?(Client)
        render json: review_json(review), status: :created
      else
        render_unprocessable(review.errors.full_messages)
      end
    end

    private

    def set_request
      @request = Request.find_by(id: params[:request_id])
      render_not_found unless @request
    end

    def review_params
      params.permit(:rating, :body)
    end

    def update_provider_rating
      provider = @request.provider
      avg = Review.joins(:request)
                  .where(requests: { provider_id: provider.id }, author_type: "Client")
                  .average(:rating)
      provider.update!(rating: avg.to_f.round(2)) if avg
    end

    def review_json(review)
      {
        id: review.id,
        request_id: review.request_id,
        rating: review.rating,
        body: review.body,
        author_type: review.author_type,
        author_id: review.author_id,
        created_at: review.created_at
      }
    end
  end
end
