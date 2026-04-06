require "rails_helper"

RSpec.describe "Api::Cards", type: :request do
  let(:client) { create(:client) }
  let(:provider) { create(:provider) }
  let(:card_params) do
    {
      token: "tok_test_#{SecureRandom.hex(8)}",
      last_four: "4242",
      brand: "visa",
      exp_month: 12,
      exp_year: 2028
    }
  end

  describe "GET /api/cards" do
    it "returns client's cards" do
      create(:card, client: client)
      create(:card, client: client)

      get "/api/cards", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(2)
    end

    it "returns 403 for provider" do
      get "/api/cards", headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/cards" do
    it "creates a card" do
      post "/api/cards", params: card_params, headers: auth_headers(client)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["last_four"]).to eq("4242")
    end

    it "auto-defaults first card" do
      post "/api/cards", params: card_params, headers: auth_headers(client)
      body = JSON.parse(response.body)
      expect(body["default"]).to be true
    end

    it "does not auto-default second card" do
      create(:card, :default, client: client)
      post "/api/cards", params: card_params, headers: auth_headers(client)
      body = JSON.parse(response.body)
      expect(body["default"]).to be false
    end

    it "returns validation error for missing fields" do
      post "/api/cards", params: { brand: "visa" }, headers: auth_headers(client)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 403 for provider" do
      post "/api/cards", params: card_params, headers: auth_headers(provider)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/cards/:id" do
    it "deletes client's card" do
      card = create(:card, client: client)
      delete "/api/cards/#{card.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for another client's card" do
      other_client = create(:client)
      card = create(:card, client: other_client)
      delete "/api/cards/#{card.id}", headers: auth_headers(client)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/cards/:id/default" do
    it "sets card as default" do
      card1 = create(:card, :default, client: client)
      card2 = create(:card, client: client)

      patch "/api/cards/#{card2.id}/default", headers: auth_headers(client)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["default"]).to be true
      expect(card1.reload.default).to be false
    end
  end
end
