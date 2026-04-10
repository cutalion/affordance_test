require "rails_helper"

RSpec.describe "Api::Orders", type: :request do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }

  describe "GET /api/orders" do
    it "returns client's own orders" do
      create(:order, client: client, provider: provider)
      create(:order) # other client's order

      get "/api/orders", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end

    it "returns provider's own orders" do
      create(:order, client: client, provider: provider)
      create(:order) # other provider's order

      get "/api/orders", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end

    it "filters by state" do
      create(:order, :confirmed, client: client, provider: provider)
      create(:order, client: client, provider: provider)

      get "/api/orders", params: { state: "confirmed" }, headers: auth_headers(client)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["state"]).to eq("confirmed")
    end

    it "returns 401 without auth" do
      get "/api/orders"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/orders/:id" do
    let(:order) { create(:order, client: client, provider: provider) }

    it "shows order details" do
      get "/api/orders/#{order.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(order.id)
      expect(body).to have_key("notes")
      expect(body).to have_key("cancel_reason")
    end

    it "returns 404 for unknown order" do
      get "/api/orders/99999", headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/orders" do
    let(:order_params) do
      {
        provider_id: provider.id,
        scheduled_at: 3.days.from_now.iso8601,
        duration_minutes: 120,
        amount_cents: 350_000,
        currency: "RUB"
      }
    end

    it "creates an order for a client" do
      post "/api/orders", params: order_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["state"]).to eq("pending")
    end

    it "returns 403 for provider" do
      post "/api/orders", params: order_params, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for non-existent provider" do
      post "/api/orders", params: order_params.merge(provider_id: 99999), headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end

    it "returns validation errors for missing fields" do
      post "/api/orders", params: { provider_id: provider.id }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/orders/:id/confirm" do
    let(:order) { create(:order, client: client, provider: provider) }

    it "confirms order as provider" do
      patch "/api/orders/#{order.id}/confirm", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("confirmed")
    end

    it "returns 403 for client" do
      patch "/api/orders/#{order.id}/confirm", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns error when wrong provider tries to confirm" do
      other_provider = create(:provider)
      patch "/api/orders/#{order.id}/confirm", headers: auth_headers(other_provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/orders/:id/start" do
    let(:order) { create(:order, :confirmed, client: client, provider: provider) }

    it "starts a confirmed order" do
      patch "/api/orders/#{order.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("in_progress")
    end

    it "returns error when trying to start a pending order" do
      pending_order = create(:order, client: client, provider: provider)
      patch "/api/orders/#{pending_order.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/orders/:id/complete" do
    let(:order) { create(:order, :in_progress, client: client, provider: provider) }

    it "completes an in_progress order" do
      patch "/api/orders/#{order.id}/complete", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("completed")
    end
  end

  describe "PATCH /api/orders/:id/cancel" do
    let(:order) { create(:order, client: client, provider: provider) }

    it "cancels order as client with reason" do
      patch "/api/orders/#{order.id}/cancel", params: { reason: "Changed plans" }, headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("canceled")
    end

    it "returns error without reason" do
      patch "/api/orders/#{order.id}/cancel", headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 403 for provider" do
      patch "/api/orders/#{order.id}/cancel", params: { reason: "test" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns error when canceling in_progress order" do
      in_progress_order = create(:order, :in_progress, client: client, provider: provider)
      patch "/api/orders/#{in_progress_order.id}/cancel", params: { reason: "test" }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/orders/:id/reject" do
    let(:order) { create(:order, :confirmed, client: client, provider: provider) }

    it "rejects order as provider with reason" do
      patch "/api/orders/#{order.id}/reject", params: { reason: "Cannot make it" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("rejected")
    end

    it "returns error without reason" do
      patch "/api/orders/#{order.id}/reject", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
