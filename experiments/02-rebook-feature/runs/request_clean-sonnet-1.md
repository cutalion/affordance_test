# Experiment: 02-rebook-feature
# App: request_clean | Model: sonnet | Run: 1
# Branch: experiment/02-rebook-feature/request_clean/sonnet/run-1

---

## Claude Output

Done. Here's what was added:

**Route:** `POST /api/requests/:id/rebook`

**Behavior:**
- Client-only (returns 403 for providers)
- Only the request's own client can rebook (returns 403 otherwise)
- Requires `scheduled_at` param for the new appointment time
- Reuses `provider`, `location`, `duration_minutes`, `amount_cents`, and `currency` from the original request
- Optionally accepts `notes` for the new request
- Returns the new request as `201 Created`, going through the normal `CreateService` flow (creates a payment, notifies the provider)

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..110ba24 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -34,6 +34,40 @@ def create
       end
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      unless @request.client_id == client.id
+        return render json: { error: "Forbidden" }, status: :forbidden
+      end
+
+      if params[:scheduled_at].blank?
+        return render_unprocessable(["Scheduled at is required"])
+      end
+
+      rebook_params = {
+        scheduled_at: params[:scheduled_at],
+        duration_minutes: @request.duration_minutes,
+        location: @request.location,
+        amount_cents: @request.amount_cents,
+        currency: @request.currency,
+        notes: params[:notes]
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
index 86b84c8..a4b2219 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -180,4 +180,64 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/requests/:id/rebook" do
+    let(:original_request) do
+      create(:request, :completed,
+        client: client,
+        provider: provider,
+        duration_minutes: 90,
+        location: "123 Main St",
+        amount_cents: 500_000,
+        currency: "RUB"
+      )
+    end
+
+    it "creates a new request reusing provider, location, and duration" do
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["duration_minutes"]).to eq(90)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["amount_cents"]).to eq(500_000)
+      expect(body["id"]).not_to eq(original_request.id)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 403 when a different client tries to rebook" do
+      other_client = create(:client)
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns validation error when scheduled_at is missing" do
+      post "/api/requests/#{original_request.id}/rebook",
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
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
 end
```
