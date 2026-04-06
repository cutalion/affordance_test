require "rails_helper"

RSpec.describe "Api::Requests", type: :request do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }

  describe "GET /api/requests" do
    it "returns client's own requests" do
      create(:request, client: client, provider: provider)
      create(:request) # other client's request

      get "/api/requests", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end

    it "returns provider's own requests" do
      create(:request, client: client, provider: provider)
      create(:request) # other provider's request

      get "/api/requests", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end

    it "filters by state" do
      create(:request, :accepted, client: client, provider: provider)
      create(:request, client: client, provider: provider)

      get "/api/requests", params: { state: "accepted" }, headers: auth_headers(client)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["state"]).to eq("accepted")
    end

    it "returns 401 without auth" do
      get "/api/requests"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/requests/:id" do
    let(:req) { create(:request, client: client, provider: provider) }

    it "shows request details" do
      get "/api/requests/#{req.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(req.id)
      expect(body).to have_key("notes")
      expect(body).to have_key("cancel_reason")
    end

    it "returns 404 for unknown request" do
      get "/api/requests/99999", headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/requests" do
    let(:request_params) do
      {
        provider_id: provider.id,
        scheduled_at: 3.days.from_now.iso8601,
        duration_minutes: 120,
        amount_cents: 350_000,
        currency: "RUB"
      }
    end

    it "creates a request for a client" do
      post "/api/requests", params: request_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["state"]).to eq("created")
    end

    it "returns 403 for provider" do
      post "/api/requests", params: request_params, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for non-existent provider" do
      post "/api/requests", params: request_params.merge(provider_id: 99999), headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end

    it "returns validation errors for missing fields" do
      post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/requests/direct" do
    let(:direct_params) do
      {
        client_id: client.id,
        scheduled_at: 3.days.from_now.iso8601,
        duration_minutes: 120,
        amount_cents: 350_000,
        currency: "RUB"
      }
    end

    it "creates a request in created_accepted state as provider" do
      post "/api/requests/direct", params: direct_params, headers: auth_headers(provider)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["state"]).to eq("created_accepted")
    end

    it "returns 403 for client" do
      post "/api/requests/direct", params: direct_params, headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for non-existent client" do
      post "/api/requests/direct", params: direct_params.merge(client_id: 99999), headers: auth_headers(provider)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/requests/:id/accept" do
    let(:req) { create(:request, client: client, provider: provider) }

    it "accepts request as provider" do
      patch "/api/requests/#{req.id}/accept", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("accepted")
    end

    it "returns 403 for client" do
      patch "/api/requests/#{req.id}/accept", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns error when wrong provider tries to accept" do
      other_provider = create(:provider)
      patch "/api/requests/#{req.id}/accept", headers: auth_headers(other_provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/requests/:id/decline" do
    let(:req) { create(:request, client: client, provider: provider) }

    it "declines request as provider" do
      patch "/api/requests/#{req.id}/decline", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("declined")
    end

    it "returns 403 for client" do
      patch "/api/requests/#{req.id}/decline", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/requests/:id/start" do
    let(:req) { create(:request, :accepted, client: client, provider: provider) }

    it "starts an accepted request" do
      patch "/api/requests/#{req.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("started")
    end

    it "returns error when trying to start a created request" do
      created_request = create(:request, client: client, provider: provider)
      patch "/api/requests/#{created_request.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/requests/:id/fulfill" do
    let(:req) { create(:request, :started, client: client, provider: provider) }

    it "fulfills a started request" do
      patch "/api/requests/#{req.id}/fulfill", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("fulfilled")
    end
  end

  describe "PATCH /api/requests/:id/cancel" do
    let(:req) { create(:request, client: client, provider: provider) }

    it "cancels request as client with reason" do
      patch "/api/requests/#{req.id}/cancel", params: { reason: "Changed plans" }, headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("canceled")
    end

    it "returns error without reason" do
      patch "/api/requests/#{req.id}/cancel", headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 403 for provider" do
      patch "/api/requests/#{req.id}/cancel", params: { reason: "test" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns error when canceling started request" do
      started_request = create(:request, :started, client: client, provider: provider)
      patch "/api/requests/#{started_request.id}/cancel", params: { reason: "test" }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/requests/:id/reject" do
    let(:req) { create(:request, :accepted, client: client, provider: provider) }

    it "rejects request as provider with reason" do
      patch "/api/requests/#{req.id}/reject", params: { reason: "Cannot make it" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("rejected")
    end

    it "returns error without reason" do
      patch "/api/requests/#{req.id}/reject", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
