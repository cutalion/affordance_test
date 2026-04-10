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
        request = create(:request)
        get "/admin/requests", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(request.client.name)
        expect(response.body).to include(request.provider.name)
      end

      it "filters by state" do
        completed_request = create(:request, :completed)
        pending_request = create(:request)

        get "/admin/requests", params: { state: "completed" }, headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(completed_request.client.name)
      end

      it "filters by date range" do
        request = create(:request, scheduled_at: 2.days.from_now)
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
        request = create(:request)
        get "/admin/requests/#{request.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and shows request details" do
        request = create(:request)
        get "/admin/requests/#{request.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(request.client.name)
        expect(response.body).to include(request.provider.name)
        expect(response.body).to include(request.state)
      end

      it "shows payment info when present" do
        request = create(:request, :with_payment)
        get "/admin/requests/#{request.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Payment")
      end

      it "shows location and notes" do
        request = create(:request)
        get "/admin/requests/#{request.id}", headers: admin_auth_headers
        expect(response.body).to include(request.location)
      end
    end
  end
end
