require "rails_helper"

RSpec.describe "Api::Reviews", type: :request do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:order) { create(:order, :completed, client: client, provider: provider) }

  describe "GET /api/orders/:order_id/reviews" do
    it "returns reviews for an order" do
      create(:review, order: order, author: client)

      get "/api/orders/#{order.id}/reviews", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end
  end

  describe "POST /api/orders/:order_id/reviews" do
    let(:review_params) { { rating: 5, body: "Excellent service!" } }

    it "creates a review successfully" do
      post "/api/orders/#{order.id}/reviews", params: review_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["rating"]).to eq(5)
      expect(body["author_type"]).to eq("Client")
    end

    it "updates provider rating when client reviews" do
      provider.update!(rating: 3.0)
      post "/api/orders/#{order.id}/reviews", params: { rating: 5, body: "Great!" }, headers: auth_headers(client)
      expect(provider.reload.rating).to be > 3.0
    end

    it "returns error for invalid rating" do
      post "/api/orders/#{order.id}/reviews", params: { rating: 6 }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns error for duplicate review" do
      create(:review, order: order, author: client)
      post "/api/orders/#{order.id}/reviews", params: review_params, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns error for non-completed order" do
      pending_order = create(:order, client: client, provider: provider)
      post "/api/orders/#{pending_order.id}/reviews", params: review_params, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "allows provider to review a completed order" do
      post "/api/orders/#{order.id}/reviews", params: { rating: 4, body: "Good client" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["author_type"]).to eq("Provider")
    end
  end
end
