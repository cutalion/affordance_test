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
      create(:request, :confirmed, client: client, provider: provider)
      create(:request, client: client, provider: provider)

      get "/api/requests", params: { state: "confirmed" }, headers: auth_headers(client)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["state"]).to eq("confirmed")
    end

    it "returns 401 without auth" do
      get "/api/requests"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/requests/:id" do
    let(:request) { create(:request, client: client, provider: provider) }

    it "shows request details" do
      get "/api/requests/#{request.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(request.id)
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

    it "creates an request for a client" do
      post "/api/requests", params: request_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["state"]).to eq("pending")
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

  describe "PATCH /api/requests/:id/confirm" do
    let(:request) { create(:request, client: client, provider: provider) }

    it "confirms request as provider" do
      patch "/api/requests/#{request.id}/confirm", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("confirmed")
    end

    it "returns 403 for client" do
      patch "/api/requests/#{request.id}/confirm", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns error when wrong provider tries to confirm" do
      other_provider = create(:provider)
      patch "/api/requests/#{request.id}/confirm", headers: auth_headers(other_provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/requests/:id/start" do
    let(:request) { create(:request, :confirmed, client: client, provider: provider) }

    it "starts a confirmed request" do
      patch "/api/requests/#{request.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("in_progress")
    end

    it "returns error when trying to start a pending request" do
      pending_request = create(:request, client: client, provider: provider)
      patch "/api/requests/#{pending_request.id}/start", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/requests/:id/complete" do
    let(:request) { create(:request, :in_progress, client: client, provider: provider) }

    it "completes an in_progress request" do
      patch "/api/requests/#{request.id}/complete", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("completed")
    end
  end

  describe "PATCH /api/requests/:id/cancel" do
    let(:request) { create(:request, client: client, provider: provider) }

    it "cancels request as client with reason" do
      patch "/api/requests/#{request.id}/cancel", params: { reason: "Changed plans" }, headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("canceled")
    end

    it "returns error without reason" do
      patch "/api/requests/#{request.id}/cancel", headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 403 for provider" do
      patch "/api/requests/#{request.id}/cancel", params: { reason: "test" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns error when canceling in_progress request" do
      in_progress_request = create(:request, :in_progress, client: client, provider: provider)
      patch "/api/requests/#{in_progress_request.id}/cancel", params: { reason: "test" }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/requests/:id/reject" do
    let(:request) { create(:request, :confirmed, client: client, provider: provider) }

    it "rejects request as provider with reason" do
      patch "/api/requests/#{request.id}/reject", params: { reason: "Cannot make it" }, headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["state"]).to eq("rejected")
    end

    it "returns error without reason" do
      patch "/api/requests/#{request.id}/reject", headers: auth_headers(provider)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
