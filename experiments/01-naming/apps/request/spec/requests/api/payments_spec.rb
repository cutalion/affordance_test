require "rails_helper"

RSpec.describe "Api::Payments", type: :request do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }

  describe "GET /api/payments" do
    it "returns payments for client's requests" do
      req = create(:request, client: client, provider: provider)
      create(:payment, request: req)
      create(:payment) # other client's payment

      get "/api/payments", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end

    it "returns payments for provider's requests" do
      req = create(:request, client: client, provider: provider)
      create(:payment, request: req)

      get "/api/payments", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
    end

    it "filters by status" do
      req1 = create(:request, client: client, provider: provider)
      req2 = create(:request, client: client, provider: provider)
      create(:payment, :held, request: req1, card: create(:card, client: client))
      create(:payment, request: req2)

      get "/api/payments", params: { status: "held" }, headers: auth_headers(client)
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["status"]).to eq("held")
    end
  end

  describe "GET /api/payments/:id" do
    let(:req) { create(:request, client: client, provider: provider) }
    let(:payment) { create(:payment, request: req) }

    it "shows payment details to client" do
      get "/api/payments/#{payment.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(payment.id)
      expect(body["status"]).to be_present
    end

    it "shows payment details to provider" do
      get "/api/payments/#{payment.id}", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for unrelated client" do
      other_client = create(:client)
      get "/api/payments/#{payment.id}", headers: auth_headers(other_client)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
