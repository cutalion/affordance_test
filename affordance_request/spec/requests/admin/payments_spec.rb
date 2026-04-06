require "rails_helper"

RSpec.describe "Admin::Payments", type: :request do
  describe "GET /admin/payments" do
    context "without authentication" do
      it "returns 401" do
        get "/admin/payments"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and lists payments" do
        req = create(:request)
        payment = create(:payment, request: req)
        get "/admin/payments", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(req.client.name)
      end

      it "filters by status" do
        req = create(:request)
        charged_payment = create(:payment, :charged, request: req)
        pending_payment = create(:payment, request: create(:request))

        get "/admin/payments", params: { status: "charged" }, headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("charged")
      end

      it "shows payment totals" do
        create_list(:payment, 2, request: create(:request))
        get "/admin/payments", headers: admin_auth_headers
        expect(response.body).to include("Payments")
      end

      it "shows fee amounts" do
        req = create(:request)
        payment = create(:payment, request: req, fee_cents: 50_000)
        get "/admin/payments", headers: admin_auth_headers
        expect(response.body).to include("500.00")
      end
    end
  end

  describe "GET /admin/payments/:id" do
    context "without authentication" do
      it "returns 401" do
        payment = create(:payment, request: create(:request))
        get "/admin/payments/#{payment.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and shows payment details" do
        req = create(:request)
        payment = create(:payment, request: req)
        get "/admin/payments/#{payment.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(payment.status)
        expect(response.body).to include(req.client.name)
      end

      it "shows request link" do
        req = create(:request)
        payment = create(:payment, request: req)
        get "/admin/payments/#{payment.id}", headers: admin_auth_headers
        expect(response.body).to include("##{req.id}")
      end

      it "shows currency" do
        req = create(:request)
        payment = create(:payment, request: req, currency: "RUB")
        get "/admin/payments/#{payment.id}", headers: admin_auth_headers
        expect(response.body).to include("RUB")
      end
    end
  end
end
