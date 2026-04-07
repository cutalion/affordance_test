# Experiment: 05-auto-assignment
# App: request | Model: sonnet | Run: 3
# Branch: experiment/05-auto-assignment/request/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**`Provider` model** (`app/models/provider.rb`):
- Added `by_rating` scope ordering by rating descending
- Added `Provider.best_available` class method returning the highest-rated active provider

**`Api::RequestsController#create`** (`app/controllers/api/requests_controller.rb`):
- `provider_id` is now optional
- If omitted, auto-assigns via `Provider.best_available`
- Returns 422 with "No available providers" if no active providers exist
- Existing 404 behavior preserved when an explicit `provider_id` is not found

**Specs added** (`spec/requests/api/requests_spec.rb`):
- Auto-assigns the highest-rated provider when `provider_id` is absent
- Returns 422 when no active providers exist

All 41 specs pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..99c461e 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
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
+        best = Provider.best_available
+        return render_unprocessable(["No available providers"]) unless best
+        best
+      end
 
       result = Requests::CreateService.new(
         client: client,
diff --git a/affordance_request/app/models/provider.rb b/affordance_request/app/models/provider.rb
index 0f43919..0904cf3 100644
--- a/affordance_request/app/models/provider.rb
+++ b/affordance_request/app/models/provider.rb
@@ -12,6 +12,11 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :by_rating, -> { order(rating: :desc) }
+
+  def self.best_available
+    active.by_rating.first
+  end
 
   private
 
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..14ff038 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -91,6 +91,34 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id" do
+      let(:base_params) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "auto-assigns the highest-rated active provider" do
+        low = create(:provider, rating: 3.0)
+        high = create(:provider, rating: 4.8)
+
+        post "/api/requests", params: base_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high.id)
+      end
+
+      it "returns unprocessable when no active providers exist" do
+        Provider.update_all(active: false)
+
+        post "/api/requests", params: base_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "POST /api/requests/direct" do
```
