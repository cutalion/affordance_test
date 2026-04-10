require "rails_helper"

RSpec.describe "Api::Clients", type: :request do
  describe "POST /api/clients/register" do
    let(:valid_params) { { email: "new@example.com", name: "New Client", phone: "+79001234567" } }

    it "registers a new client successfully" do
      post "/api/clients/register", params: valid_params
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["email"]).to eq("new@example.com")
      expect(body["api_token"]).to be_present
    end

    it "returns validation error for missing email" do
      post "/api/clients/register", params: { name: "Test" }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_present
    end

    it "returns error for duplicate email" do
      create(:client, email: "existing@example.com")
      post "/api/clients/register", params: { email: "existing@example.com", name: "Dup" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/clients/me" do
    let(:client) { create(:client) }

    it "returns current client data" do
      get "/api/clients/me", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["email"]).to eq(client.email)
    end

    it "returns 401 without auth" do
      get "/api/clients/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for provider token" do
      provider = create(:provider)
      get "/api/clients/me", headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
