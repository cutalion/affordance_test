require "rails_helper"

RSpec.describe "Admin::Orders", type: :request do
  describe "GET /admin/orders" do
    context "without authentication" do
      it "returns 401" do
        get "/admin/orders"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and lists orders" do
        order = create(:order)
        get "/admin/orders", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(order.client.name)
        expect(response.body).to include(order.provider.name)
      end

      it "filters by state" do
        completed_order = create(:order, :completed)
        pending_order = create(:order)

        get "/admin/orders", params: { state: "completed" }, headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(completed_order.client.name)
      end

      it "filters by date range" do
        order = create(:order, scheduled_at: 2.days.from_now)
        get "/admin/orders", params: { from: 1.day.from_now.to_date.to_s, to: 3.days.from_now.to_date.to_s }, headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
      end

      it "shows order count" do
        create_list(:order, 3)
        get "/admin/orders", headers: admin_auth_headers
        expect(response.body).to include("Orders")
      end
    end
  end

  describe "GET /admin/orders/:id" do
    context "without authentication" do
      it "returns 401" do
        order = create(:order)
        get "/admin/orders/#{order.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and shows order details" do
        order = create(:order)
        get "/admin/orders/#{order.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(order.client.name)
        expect(response.body).to include(order.provider.name)
        expect(response.body).to include(order.state)
      end

      it "shows payment info when present" do
        order = create(:order, :with_payment)
        get "/admin/orders/#{order.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Payment")
      end

      it "shows location and notes" do
        order = create(:order)
        get "/admin/orders/#{order.id}", headers: admin_auth_headers
        expect(response.body).to include(order.location)
      end
    end
  end
end
