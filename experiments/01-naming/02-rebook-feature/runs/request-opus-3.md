# Experiment: 02-rebook-feature
# App: request | Model: opus | Run: 3
# Branch: experiment/02-rebook-feature/request/opus/run-3

---

## Claude Output

Done. Here's what I implemented:

**`POST /api/requests/:id/rebook`** — client-only endpoint that creates a new booking based on a previous one.

**Files changed:**
- `app/services/requests/rebook_service.rb` — new service that copies provider, location, duration, amount, and currency from the original request, delegates to `CreateService`
- `app/controllers/api/requests_controller.rb` — added `rebook` action
- `config/routes.rb` — added `post :rebook` member route
- `spec/services/requests/rebook_service_spec.rb` — 7 specs covering reuse, overrides, ownership check, validation
- `spec/requests/api/requests_spec.rb` — 5 integration specs covering happy path, overrides, auth, ownership, 404

**Behavior:**
- Only the client who owns the original request can rebook
- `scheduled_at` is required (new booking time)
- `duration_minutes`, `location`, `amount_cents`, `currency` default to original values but can be overridden
- `notes` are not copied (fresh start) but can be provided
- Creates a new payment with 10% fee, notifies the provider

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..0e42ce0 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -118,6 +118,25 @@ def reject
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      result = Requests::RebookService.new(
+        original_request: @the_request,
+        client: client,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      elsif result[:error]
+        render json: { error: result[:error] }, status: :unprocessable_entity
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     private
 
     def set_request
@@ -137,6 +156,10 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request/app/services/requests/rebook_service.rb b/affordance_request/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..532d7cf
--- /dev/null
+++ b/affordance_request/app/services/requests/rebook_service.rb
@@ -0,0 +1,32 @@
+module Requests
+  class RebookService
+    def initialize(original_request:, client:, params: {})
+      @original_request = original_request
+      @client = client
+      @params = params
+    end
+
+    def call
+      return { success: false, error: "You can only rebook your own requests" } unless @original_request.client_id == @client.id
+
+      CreateService.new(
+        client: @client,
+        provider: @original_request.provider,
+        params: rebook_params
+      ).call
+    end
+
+    private
+
+    def rebook_params
+      {
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes] || @original_request.duration_minutes,
+        location: @params[:location] || @original_request.location,
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents] || @original_request.amount_cents,
+        currency: @params[:currency] || @original_request.currency
+      }
+    end
+  end
+end
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..4a162af 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -21,6 +21,7 @@
         patch :fulfill
         patch :cancel
         patch :reject
+        post :rebook
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..d849312 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -224,4 +224,58 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/requests/:id/rebook" do
+    let(:req) { create(:request, :fulfilled, client: client, provider: provider, location: "123 Main St", duration_minutes: 120) }
+
+    it "creates a new request based on the original" do
+      post "/api/requests/#{req.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("created")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(120)
+      expect(body["id"]).not_to eq(req.id)
+    end
+
+    it "allows overriding fields" do
+      post "/api/requests/#{req.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601, location: "456 Oak Ave", duration_minutes: 60 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["location"]).to eq("456 Oak Ave")
+      expect(body["duration_minutes"]).to eq(60)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{req.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when client does not own the request" do
+      other_client = create(:client)
+      post "/api/requests/#{req.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 404 for non-existent request" do
+      post "/api/requests/99999/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:not_found)
+    end
+  end
 end
diff --git a/affordance_request/spec/services/requests/rebook_service_spec.rb b/affordance_request/spec/services/requests/rebook_service_spec.rb
new file mode 100644
index 0000000..7a43a5e
--- /dev/null
+++ b/affordance_request/spec/services/requests/rebook_service_spec.rb
@@ -0,0 +1,77 @@
+require "rails_helper"
+
+RSpec.describe Requests::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_request) do
+    create(:request, :fulfilled, client: client, provider: provider,
+      location: "123 Main St", duration_minutes: 120, amount_cents: 350_000, currency: "RUB")
+  end
+  let(:params) { { scheduled_at: 5.days.from_now } }
+
+  subject(:result) { described_class.new(original_request: original_request, client: client, params: params).call }
+
+  describe "#call" do
+    context "with valid rebook" do
+      it "creates a new request with the same provider" do
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(provider)
+      end
+
+      it "reuses location from original request" do
+        expect(result[:request].location).to eq("123 Main St")
+      end
+
+      it "reuses duration from original request" do
+        expect(result[:request].duration_minutes).to eq(120)
+      end
+
+      it "reuses amount from original request" do
+        expect(result[:request].amount_cents).to eq(350_000)
+        expect(result[:request].currency).to eq("RUB")
+      end
+
+      it "creates a new request in created state" do
+        expect(result[:request].state).to eq("created")
+        expect(result[:request].id).not_to eq(original_request.id)
+      end
+
+      it "creates a pending payment" do
+        expect { result }.to change(Payment, :count).by(1)
+        expect(result[:request].payment.status).to eq("pending")
+      end
+    end
+
+    context "with overridden params" do
+      let(:params) do
+        { scheduled_at: 5.days.from_now, duration_minutes: 60, location: "456 Oak Ave", amount_cents: 200_000 }
+      end
+
+      it "uses provided params over original values" do
+        expect(result[:request].duration_minutes).to eq(60)
+        expect(result[:request].location).to eq("456 Oak Ave")
+        expect(result[:request].amount_cents).to eq(200_000)
+      end
+    end
+
+    context "when client does not own the original request" do
+      let(:other_client) { create(:client) }
+
+      subject(:result) { described_class.new(original_request: original_request, client: other_client, params: params).call }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("You can only rebook your own requests")
+      end
+    end
+
+    context "with missing scheduled_at" do
+      let(:params) { {} }
+
+      it "returns validation errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+    end
+  end
+end
```
