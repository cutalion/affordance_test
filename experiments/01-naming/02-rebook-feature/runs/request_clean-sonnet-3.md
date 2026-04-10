# Experiment: 02-rebook-feature
# App: request_clean | Model: sonnet | Run: 3
# Branch: experiment/02-rebook-feature/request_clean/sonnet/run-3

---

## Claude Output

Done. Here's what was added:

**`POST /api/requests/:id/rebook`** (client-only)

- Copies `provider`, `location`, `duration_minutes`, `currency`, and `notes` from the original request
- Requires `scheduled_at` in the request body
- Optionally accepts `amount_cents` and `notes` overrides
- Returns the new request (state: `pending`) with `201 Created`
- Returns `403` for providers, `404` for unknown original, `422` for missing `scheduled_at`

The implementation reuses `Requests::CreateService` unchanged — the controller just populates params from the original request before delegating. 5 new specs cover the happy path and all error cases, all passing.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..c3e8722 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -34,6 +34,32 @@ def create
       end
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      rebook_params = {
+        scheduled_at: params[:scheduled_at],
+        duration_minutes: @request.duration_minutes,
+        location: @request.location,
+        notes: params.key?(:notes) ? params[:notes] : @request.notes,
+        amount_cents: params[:amount_cents] || @request.amount_cents,
+        currency: @request.currency
+      }
+
+      result = Requests::CreateService.new(
+        client: client,
+        provider: @request.provider,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..564cfee 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -17,6 +17,7 @@
         patch :complete
         patch :cancel
         patch :reject
+        post :rebook
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..2d2274e 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -166,6 +166,69 @@
     end
   end
 
+  describe "POST /api/requests/:id/rebook" do
+    let(:original) do
+      create(:request, :completed,
+        client: client,
+        provider: provider,
+        duration_minutes: 90,
+        location: "Park Avenue",
+        amount_cents: 500_000,
+        currency: "RUB",
+        notes: "Original notes")
+    end
+
+    it "creates a new request copying provider, location, and duration" do
+      post "/api/requests/#{original.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["duration_minutes"]).to eq(90)
+      expect(body["location"]).to eq("Park Avenue")
+      expect(body["amount_cents"]).to eq(500_000)
+      expect(body["notes"]).to eq("Original notes")
+    end
+
+    it "allows overriding scheduled_at and amount_cents" do
+      new_time = 7.days.from_now.iso8601
+      post "/api/requests/#{original.id}/rebook",
+        params: { scheduled_at: new_time, amount_cents: 600_000 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["amount_cents"]).to eq(600_000)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{original.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns validation error when scheduled_at is missing" do
+      post "/api/requests/#{original.id}/rebook",
+        params: {},
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 404 for unknown original request" do
+      post "/api/requests/99999/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:not_found)
+    end
+  end
+
   describe "PATCH /api/requests/:id/reject" do
     let(:request) { create(:request, :confirmed, client: client, provider: provider) }
 
```
