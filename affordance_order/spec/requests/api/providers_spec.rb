require "rails_helper"

RSpec.describe "Api::Providers", type: :request do
  describe "POST /api/providers/register" do
    let(:valid_params) { { email: "provider@example.com", name: "New Provider", specialization: "cleaning" } }

    it "registers a new provider successfully" do
      post "/api/providers/register", params: valid_params
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["email"]).to eq("provider@example.com")
      expect(body["api_token"]).to be_present
    end

    it "returns validation error for missing name" do
      post "/api/providers/register", params: { email: "test@example.com" }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["errors"]).to be_present
    end
  end

  describe "GET /api/providers/me" do
    let(:provider) { create(:provider) }

    it "returns current provider data" do
      get "/api/providers/me", headers: auth_headers(provider)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["email"]).to eq(provider.email)
    end

    it "returns 401 without auth" do
      get "/api/providers/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for client token" do
      client = create(:client)
      get "/api/providers/me", headers: auth_headers(client)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
