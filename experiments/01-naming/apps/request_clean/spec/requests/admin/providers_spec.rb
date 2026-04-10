require "rails_helper"

RSpec.describe "Admin::Providers", type: :request do
  describe "GET /admin/providers" do
    context "without authentication" do
      it "returns 401" do
        get "/admin/providers"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and lists providers" do
        provider = create(:provider)
        get "/admin/providers", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(provider.name)
        expect(response.body).to include(provider.email)
      end

      it "shows specialization" do
        provider = create(:provider, specialization: "plumbing")
        get "/admin/providers", headers: admin_auth_headers
        expect(response.body).to include("plumbing")
      end

      it "shows active status" do
        create(:provider, active: true)
        get "/admin/providers", headers: admin_auth_headers
        expect(response.body).to include("Yes")
      end
    end
  end

  describe "GET /admin/providers/:id" do
    context "without authentication" do
      it "returns 401" do
        provider = create(:provider)
        get "/admin/providers/#{provider.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with authentication" do
      it "returns 200 and shows provider details" do
        provider = create(:provider)
        get "/admin/providers/#{provider.id}", headers: admin_auth_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(provider.name)
        expect(response.body).to include(provider.email)
        expect(response.body).to include(provider.specialization)
      end

      it "shows rating" do
        provider = create(:provider, rating: 4.8)
        get "/admin/providers/#{provider.id}", headers: admin_auth_headers
        expect(response.body).to include("4.8")
      end

      it "shows recent requests" do
        provider = create(:provider)
        request = create(:request, provider: provider)
        get "/admin/providers/#{provider.id}", headers: admin_auth_headers
        expect(response.body).to include("Recent Requests")
        expect(response.body).to include(request.client.name)
      end
    end
  end
end
