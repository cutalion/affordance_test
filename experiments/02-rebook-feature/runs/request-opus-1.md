# Experiment: 02-rebook-feature
# App: request | Model: opus | Run: 1
# Branch: experiment/02-rebook-feature/request/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**New endpoint**: `POST /api/requests/:id/rebook` (client-only)

**How it works**: A client sends a request to rebook based on a previous booking. The new request automatically reuses the original's provider, location, duration, and amount. The client must provide `scheduled_at` for the new booking and can optionally override `duration_minutes`, `location`, `amount_cents`, `currency`, and `notes`.

**Files changed**:
- `app/services/requests/rebook_service.rb` — new service that copies fields from the original request and creates a new one with payment
- `app/controllers/api/requests_controller.rb` — added `rebook` action
- `config/routes.rb` — added `post :rebook` member route
- `spec/requests/api/requests_spec.rb` — 5 tests covering happy path, overrides, auth, ownership, and validation

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..c940a4a 100644
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
+        params: request_params
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
diff --git a/affordance_request/app/services/requests/rebook_service.rb b/affordance_request/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..174643a
--- /dev/null
+++ b/affordance_request/app/services/requests/rebook_service.rb
@@ -0,0 +1,48 @@
+module Requests
+  class RebookService
+    def initialize(original_request:, client:, params:)
+      @original_request = original_request
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @original_request.client_id == @client.id
+        return { success: false, error: "Request does not belong to this client" }
+      end
+
+      request = Request.new(
+        client: @client,
+        provider: @original_request.provider,
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes] || @original_request.duration_minutes,
+        location: @params[:location] || @original_request.location,
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents] || @original_request.amount_cents,
+        currency: @params[:currency] || @original_request.currency
+      )
+
+      Request.transaction do
+        request.save!
+        Payment.create!(
+          request: request,
+          amount_cents: request.amount_cents,
+          currency: request.currency,
+          fee_cents: calculate_fee(request.amount_cents),
+          status: "pending"
+        )
+      end
+
+      NotificationService.notify(request.provider, :request_created, request_id: request.id)
+      { success: true, request: request }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
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
index 772331d..d923216 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -224,4 +224,56 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/requests/:id/rebook" do
+    let(:original_request) { create(:request, :fulfilled, client: client, provider: provider, location: "123 Main St", duration_minutes: 120, amount_cents: 350_000) }
+
+    it "creates a new request reusing provider, location, and duration" do
+      new_time = 5.days.from_now.iso8601
+      post "/api/requests/#{original_request.id}/rebook", params: { scheduled_at: new_time }, headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("created")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(120)
+      expect(body["amount_cents"]).to eq(350_000)
+      expect(body["id"]).not_to eq(original_request.id)
+    end
+
+    it "allows overriding duration and location" do
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601, duration_minutes: 60, location: "456 Oak Ave" },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["duration_minutes"]).to eq(60)
+      expect(body["location"]).to eq("456 Oak Ave")
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when rebooking another client's request" do
+      other_client = create(:client)
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns validation errors for missing scheduled_at" do
+      post "/api/requests/#{original_request.id}/rebook",
+        params: {},
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
```
