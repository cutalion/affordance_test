# Experiment: 02-rebook-feature
# App: request | Model: sonnet | Run: 2
# Branch: experiment/02-rebook-feature/request/sonnet/run-2

---

## Claude Output

Done. Here's a summary of every change made:

---

### What was added

**`app/services/requests/rebook_service.rb`** (new file)  
Thin service that mirrors `CreateService`. Given an `original_request`, a `client`, and params, it:
- Verifies the client owns the original request (returns `{ error: "Forbidden" }` otherwise).
- Builds a new `Request` copying `provider`, `location`, and `duration_minutes` from the original; uses the supplied `scheduled_at`, and falls back to the original's `amount_cents` / `currency` if not overridden.
- Wraps the `Request` + `Payment` creation in a transaction and fires the `request_created` notification to the provider.

**`config/routes.rb`**  
Added `post :rebook` inside the `resources :requests … member` block → `POST /api/requests/:id/rebook`.

**`app/controllers/api/requests_controller.rb`**  
- Added `:rebook` to the `before_action :set_request` list.
- Added `rebook` action (client-only) that calls `RebookService` and renders the new request detail or the appropriate error.
- Added `rebook_params` strong-params helper (permits `scheduled_at`, `amount_cents`, `currency`, `notes`).

**`spec/requests/api/requests_spec.rb`**  
6 new examples covering: happy path (fields copied correctly), overriding optional fields, missing `scheduled_at` → 422, wrong client → 403, provider → 403, unknown request → 404. All 33 specs pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..7efee9c 100644
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
+      elsif result[:error] == "Forbidden"
+        render_forbidden
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
+      params.permit(:scheduled_at, :amount_cents, :currency, :notes)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request/app/services/requests/rebook_service.rb b/affordance_request/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..25cf42d
--- /dev/null
+++ b/affordance_request/app/services/requests/rebook_service.rb
@@ -0,0 +1,48 @@
+module Requests
+  class RebookService
+    def initialize(original_request:, client:, params:)
+      @original = original_request
+      @client   = client
+      @params   = params
+    end
+
+    def call
+      unless @original.client_id == @client.id
+        return { success: false, error: "Forbidden" }
+      end
+
+      request = Request.new(
+        client:           @client,
+        provider:         @original.provider,
+        location:         @original.location,
+        duration_minutes: @original.duration_minutes,
+        scheduled_at:     @params[:scheduled_at],
+        amount_cents:     @params.fetch(:amount_cents, @original.amount_cents),
+        currency:         @params.fetch(:currency, @original.currency),
+        notes:            @params[:notes]
+      )
+
+      Request.transaction do
+        request.save!
+        Payment.create!(
+          request:      request,
+          amount_cents: request.amount_cents,
+          currency:     request.currency,
+          fee_cents:    calculate_fee(request.amount_cents),
+          status:       "pending"
+        )
+      end
+
+      NotificationService.notify(@original.provider, :request_created, request_id: request.id)
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
index 772331d..6b75ade 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -210,6 +210,68 @@
     end
   end
 
+  describe "POST /api/requests/:id/rebook" do
+    let(:original) { create(:request, client: client, provider: provider, location: "123 Main St", duration_minutes: 90, amount_cents: 350_000) }
+
+    it "creates a new request reusing provider, location, and duration" do
+      post "/api/requests/#{original.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("created")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(90)
+      expect(body["amount_cents"]).to eq(350_000)
+    end
+
+    it "allows overriding amount_cents and notes" do
+      post "/api/requests/#{original.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601, amount_cents: 400_000, notes: "New notes" },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["amount_cents"]).to eq(400_000)
+      expect(body["notes"]).to eq("New notes")
+    end
+
+    it "returns 422 when scheduled_at is missing" do
+      post "/api/requests/#{original.id}/rebook",
+        params: {},
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 when another client tries to rebook" do
+      other_client = create(:client)
+      post "/api/requests/#{original.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 403 for a provider" do
+      post "/api/requests/#{original.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for unknown request" do
+      post "/api/requests/99999/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:not_found)
+    end
+  end
+
   describe "PATCH /api/requests/:id/reject" do
     let(:req) { create(:request, :accepted, client: client, provider: provider) }
 
```
