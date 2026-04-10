# Experiment: 05-auto-assignment
# App: request | Model: sonnet | Run: 1
# Branch: experiment/05-auto-assignment/request/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**`app/models/provider.rb`** — added `best_available` scope:
```ruby
scope :best_available, -> { active.order(rating: :desc) }
```

**`app/controllers/api/requests_controller.rb`** — `create` action now makes `provider_id` optional:
- If `provider_id` is given: finds that specific provider, 404 if not found
- If omitted: selects `Provider.best_available.first`, 422 if no active providers exist

**`spec/requests/api/requests_spec.rb`** — 3 new tests covering:
- Auto-assigns the highest-rated active provider
- Skips inactive providers
- Returns 422 when no active providers exist

All 30 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..b9b474f 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -18,8 +18,14 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = if params[:provider_id].present?
+        Provider.find_by(id: params[:provider_id])
+      else
+        Provider.best_available.first
+      end
+
+      return render_not_found if params[:provider_id].present? && provider.nil?
+      return render_unprocessable(["No available providers"]) if provider.nil?
 
       result = Requests::CreateService.new(
         client: client,
diff --git a/affordance_request/app/models/provider.rb b/affordance_request/app/models/provider.rb
index 0f43919..8806f89 100644
--- a/affordance_request/app/models/provider.rb
+++ b/affordance_request/app/models/provider.rb
@@ -12,6 +12,7 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :best_available, -> { active.order(rating: :desc) }
 
   private
 
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..e389544 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -91,6 +91,41 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id" do
+      let(:params_without_provider) { request_params.except(:provider_id) }
+
+      it "auto-assigns the highest-rated active provider" do
+        low_rated = create(:provider, rating: 3.0)
+        high_rated = create(:provider, rating: 5.0)
+
+        post "/api/requests", params: params_without_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "skips inactive providers when auto-assigning" do
+        provider # ensure outer provider is created first
+        Provider.update_all(active: false)
+        active_provider = create(:provider, rating: 4.0, active: true)
+
+        post "/api/requests", params: params_without_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(active_provider.id)
+      end
+
+      it "returns 422 when no active providers are available" do
+        provider # ensure outer provider is created first
+        Provider.update_all(active: false)
+
+        post "/api/requests", params: params_without_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+        body = JSON.parse(response.body)
+        expect(body["errors"]).to include("No available providers")
+      end
+    end
   end
 
   describe "POST /api/requests/direct" do
```
