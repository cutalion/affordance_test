# Experiment: 02-rebook-feature
# App: request_clean | Model: opus | Run: 2
# Branch: experiment/02-rebook-feature/request_clean/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**`POST /api/requests/:id/rebook`** — creates a new pending request by copying from a previous one.

- **Reused fields**: provider, location, duration, amount, currency
- **Required**: `scheduled_at` (new booking time)
- **Optional overrides**: `duration_minutes`, `location`, `notes`, `amount_cents`, `currency`
- **Access control**: only the client who owns the original request can rebook; providers get 403, other clients get 404
- **Reuses** the existing `Requests::CreateService`, so payment creation and provider notification happen automatically

5 new specs cover the happy path, field overrides, missing scheduled_at validation, provider rejection, and cross-client access.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..c3c5ab7 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,27 @@ def reject
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      unless @request.client_id == client.id
+        return render_not_found
+      end
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
     private
 
     def set_request
@@ -109,6 +130,18 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      overrides = params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+      {
+        scheduled_at: overrides[:scheduled_at],
+        duration_minutes: overrides[:duration_minutes] || @request.duration_minutes,
+        location: overrides[:location] || @request.location,
+        notes: overrides[:notes],
+        amount_cents: overrides[:amount_cents] || @request.amount_cents,
+        currency: overrides[:currency] || @request.currency
+      }
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
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
index 86b84c8..9f79ac1 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -166,6 +166,61 @@
     end
   end
 
+  describe "POST /api/requests/:id/rebook" do
+    let!(:original_request) { create(:request, :completed, client: client, provider: provider, location: "123 Main St", duration_minutes: 90, amount_cents: 500_000, currency: "RUB") }
+
+    it "creates a new request reusing provider, location, and duration" do
+      post "/api/requests/#{original_request.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601 },
+           headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(90)
+      expect(body["amount_cents"]).to eq(500_000)
+      expect(body["id"]).not_to eq(original_request.id)
+    end
+
+    it "allows overriding fields" do
+      post "/api/requests/#{original_request.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601, duration_minutes: 60, location: "456 Oak Ave" },
+           headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["duration_minutes"]).to eq(60)
+      expect(body["location"]).to eq("456 Oak Ave")
+    end
+
+    it "returns validation error without scheduled_at" do
+      post "/api/requests/#{original_request.id}/rebook",
+           params: {},
+           headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{original_request.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601 },
+           headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for another client's request" do
+      other_client = create(:client)
+      post "/api/requests/#{original_request.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601 },
+           headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:not_found)
+    end
+  end
+
   describe "PATCH /api/requests/:id/reject" do
     let(:request) { create(:request, :confirmed, client: client, provider: provider) }
 
```
