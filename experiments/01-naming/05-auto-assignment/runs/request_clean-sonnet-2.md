# Experiment: 05-auto-assignment
# App: request_clean | Model: sonnet | Run: 2
# Branch: experiment/05-auto-assignment/request_clean/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**`Provider.best_available`** (`app/models/provider.rb`) — returns the active provider with the highest rating, or `nil` if none exist.

**Controller auto-assignment** (`app/controllers/api/requests_controller.rb`) — when `POST /api/requests` is called without `provider_id`, it calls `Provider.best_available`. If a provider is found, the request is created with them. If no active providers exist, it returns 422 with `"No active providers available"`. Explicit `provider_id` still behaves as before (404 if not found).

**5 new tests** covering: highest-rated selection, inactive provider exclusion, nil when no active providers, API auto-assignment, and API 422 fallback. All 270 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..6079cc1 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -18,8 +18,13 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = if params[:provider_id].present?
+        Provider.find_by(id: params[:provider_id])
+          .tap { |p| return render_not_found unless p }
+      else
+        Provider.best_available
+          .tap { |p| return render_unprocessable(["No active providers available"]) unless p }
+      end
 
       result = Requests::CreateService.new(
         client: client,
diff --git a/affordance_request_clean/app/models/provider.rb b/affordance_request_clean/app/models/provider.rb
index 0f43919..24db94b 100644
--- a/affordance_request_clean/app/models/provider.rb
+++ b/affordance_request_clean/app/models/provider.rb
@@ -13,6 +13,10 @@ class Provider < ApplicationRecord
 
   scope :active, -> { where(active: true) }
 
+  def self.best_available
+    active.order(rating: :desc).first
+  end
+
   private
 
   def generate_api_token
diff --git a/affordance_request_clean/spec/models/provider_spec.rb b/affordance_request_clean/spec/models/provider_spec.rb
index ad86fbe..67c4587 100644
--- a/affordance_request_clean/spec/models/provider_spec.rb
+++ b/affordance_request_clean/spec/models/provider_spec.rb
@@ -65,4 +65,23 @@
       expect(provider.notification_preferences).to include("push" => true, "sms" => true, "email" => true)
     end
   end
+
+  describe ".best_available" do
+    it "returns the active provider with the highest rating" do
+      low_rated = create(:provider, active: true, rating: 3.0)
+      high_rated = create(:provider, active: true, rating: 4.8)
+      expect(Provider.best_available).to eq(high_rated)
+    end
+
+    it "ignores inactive providers" do
+      inactive = create(:provider, active: false, rating: 5.0)
+      active = create(:provider, active: true, rating: 3.0)
+      expect(Provider.best_available).to eq(active)
+    end
+
+    it "returns nil when no active providers exist" do
+      create(:provider, active: false)
+      expect(Provider.best_available).to be_nil
+    end
+  end
 end
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..26266bf 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -91,6 +91,34 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id" do
+      let(:request_params_no_provider) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "auto-assigns the highest-rated active provider" do
+        low_rated = create(:provider, active: true, rating: 3.0)
+        high_rated = create(:provider, active: true, rating: 4.9)
+
+        post "/api/requests", params: request_params_no_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "returns 422 when no active providers are available" do
+        create(:provider, active: false)
+
+        post "/api/requests", params: request_params_no_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "PATCH /api/requests/:id/confirm" do
```
