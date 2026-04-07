require "rails_helper"

RSpec.describe "Api::Reviews", type: :request do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:request) { create(:request, :completed, client: client, provider: provider) }

  describe "GET /api/requests/:request_id/reviews" do
    it "returns reviews for an request" do
      create(:review, request: request, author: client)

      get "/api/requests/#{request.id}/reviews", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end
  end

  describe "POST /api/requests/:request_id/reviews" do
    let(:review_params) { { rating: 5, body: "Excellent service!" } }

    it "creates a review successfully" do
      post "/api/requests/#{request.id}/reviews", params: review_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["rating"]).to eq(5)
      expect(body["author_type"]).to eq("Client")
    end

    it "updates provider rating when client reviews" do
      provider.update!(rating: 3.0)
      post "/api/requests/#{request.id}/reviews", params: { rating: 5, body: "Great!" }, headers: auth_headers(client)
      expect(provider.reload.rating).to be > 3.0
    end

    it "returns error for invalid rating" do
      post "/api/requests/#{request.id}/reviews", params: { rating: 6 }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns error for duplicate review" do
      create(:review, request: request, author: client)
      post "/api/requests/#{request.id}/reviews", params: review_params, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns error for non-completed request" do
      pending_request = create(:request, client: client, provider: provider)
      post "/api/requests/#{pending_request.id}/reviews", params: review_params, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "allows provider to review a completed request" do
      post "/api/requests/#{request.id}/reviews", params: { rating: 4, body: "Good client" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["author_type"]).to eq("Provider")
    end
  end
end
