require "rails_helper"

RSpec.describe "Admin::Dashboard", type: :request do
  describe "GET /admin" do
    context "without authentication" do
      it "returns 401" do
        get "/admin"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200" do
        get "/admin", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
      end

      it "renders dashboard content" do
        create(:client)
        create(:provider)

        get "/admin", headers: admin_auth_headers
        expect(response.body).to include("Dashboard")
        expect(response.body).to include("Clients")
        expect(response.body).to include("Providers")
      end

      it "shows order state counts" do
        create(:order, :completed)
        create(:order)

        get "/admin", headers: admin_auth_headers
        expect(response.body).to include("Orders")
      end

      it "shows recent orders" do
        order = create(:order)
        get "/admin", headers: admin_auth_headers
        expect(response.body).to include(order.client.name)
        expect(response.body).to include(order.provider.name)
      end
    end
  end

  describe "GET /admin/dashboard" do
    it "returns 401 without auth" do
      get "/admin/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with auth" do
      get "/admin/dashboard", headers: admin_auth_headers
      expect(response).to have_http_status(:ok)
    end
  end
end
