require "rails_helper"

RSpec.describe "Admin::Requests", type: :request do
  describe "GET /admin/requests" do
    context "without authentication" do
      it "returns 401" do
        get "/admin/requests"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and lists requests" do
        req = create(:request)
        get "/admin/requests", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(req.client.name)
        expect(response.body).to include(req.provider.name)
      end

      it "filters by state" do
        fulfilled_request = create(:request, :fulfilled)
        created_request = create(:request)

        get "/admin/requests", params: { state: "fulfilled" }, headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(fulfilled_request.client.name)
      end

      it "filters by date range" do
        req = create(:request, scheduled_at: 2.days.from_now)
        get "/admin/requests", params: { from: 1.day.from_now.to_date.to_s, to: 3.days.from_now.to_date.to_s }, headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
      end

      it "shows request count" do
        create_list(:request, 3)
        get "/admin/requests", headers: admin_auth_headers
        expect(response.body).to include("Requests")
      end
    end
  end

  describe "GET /admin/requests/:id" do
    context "without authentication" do
      it "returns 401" do
        req = create(:request)
        get "/admin/requests/#{req.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and shows request details" do
        req = create(:request)
        get "/admin/requests/#{req.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(req.client.name)
        expect(response.body).to include(req.provider.name)
        expect(response.body).to include(req.state)
      end

      it "shows payment info when present" do
        req = create(:request, :with_payment)
        get "/admin/requests/#{req.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Payment")
      end

      it "shows location and notes" do
        req = create(:request)
        get "/admin/requests/#{req.id}", headers: admin_auth_headers
        expect(response.body).to include(req.location)
      end
    end
  end
end
