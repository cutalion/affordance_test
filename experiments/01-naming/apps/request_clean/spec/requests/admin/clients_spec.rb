require "rails_helper"

RSpec.describe "Admin::Clients", type: :request do
  describe "GET /admin/clients" do
    context "without authentication" do
      it "returns 401" do
        get "/admin/clients"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and lists clients" do
        client = create(:client)
        get "/admin/clients", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(client.name)
        expect(response.body).to include(client.email)
      end

      it "shows total count" do
        create_list(:client, 3)
        get "/admin/clients", headers: admin_auth_headers
        expect(response.body).to include("Clients")
      end

      it "shows phone numbers" do
        client = create(:client)
        get "/admin/clients", headers: admin_auth_headers
        expect(response.body).to include(client.phone)
      end
    end
  end

  describe "GET /admin/clients/:id" do
    context "without authentication" do
      it "returns 401" do
        client = create(:client)
        get "/admin/clients/#{client.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and shows client details" do
        client = create(:client)
        get "/admin/clients/#{client.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(client.name)
        expect(response.body).to include(client.email)
      end

      it "shows recent requests" do
        client = create(:client)
        request = create(:request, client: client)
        get "/admin/clients/#{client.id}", headers: admin_auth_headers
        expect(response.body).to include("Recent Requests")
        expect(response.body).to include(request.provider.name)
      end

      it "shows cards section" do
        client = create(:client)
        card = create(:card, client: client, default: true)
        get "/admin/clients/#{client.id}", headers: admin_auth_headers
        expect(response.body).to include(card.last_four)
      end
    end
  end
end
