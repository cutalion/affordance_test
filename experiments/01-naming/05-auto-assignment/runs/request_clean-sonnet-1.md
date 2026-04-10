# Experiment: 05-auto-assignment
# App: request_clean | Model: sonnet | Run: 1
# Branch: experiment/05-auto-assignment/request_clean/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**`app/models/provider.rb`** — Added `scope :by_rating, -> { order(rating: :desc) }`

**`app/controllers/api/requests_controller.rb`** — Updated `create` to auto-assign when `provider_id` is absent:
- If `provider_id` is provided: behaves as before (404 if not found)
- If `provider_id` is omitted: selects `Provider.active.by_rating.first` (highest-rated active provider), returns 422 if none available

**`spec/requests/api/requests_spec.rb`** — Two new tests covering both auto-assignment cases. All 40 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..9d1f9ea 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -18,8 +18,15 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = if params[:provider_id].present?
+        found = Provider.find_by(id: params[:provider_id])
+        return render_not_found unless found
+        found
+      else
+        best = Provider.active.by_rating.first
+        return render_unprocessable(["No available providers"]) unless best
+        best
+      end
 
       result = Requests::CreateService.new(
         client: client,
diff --git a/affordance_request_clean/app/models/provider.rb b/affordance_request_clean/app/models/provider.rb
index 0f43919..edd3e72 100644
--- a/affordance_request_clean/app/models/provider.rb
+++ b/affordance_request_clean/app/models/provider.rb
@@ -12,6 +12,7 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :by_rating, -> { order(rating: :desc) }
 
   private
 
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..9a22a05 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -91,6 +91,32 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "when provider_id is omitted" do
+      let(:params_without_provider) { request_params.except(:provider_id) }
+
+      it "auto-assigns the highest-rated active provider" do
+        low_rated = create(:provider, rating: 3.0)
+        high_rated = create(:provider, rating: 4.8)
+
+        post "/api/requests", params: params_without_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "returns unprocessable when no active providers exist" do
+        create(:provider, active: false)
+        no_provider_params = {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+        post "/api/requests", params: no_provider_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "PATCH /api/requests/:id/confirm" do
```
