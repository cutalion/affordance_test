# Experiment: 05-auto-assignment
# App: order | Model: sonnet | Run: 2
# Branch: experiment/05-auto-assignment/order/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**`app/models/provider.rb`** — added `best_available` scope:
```ruby
scope :best_available, -> { active.order(rating: :desc) }
```

**`app/controllers/api/orders_controller.rb`** — `create` action now auto-assigns when `provider_id` is absent:
- If `provider_id` is present → look up that specific provider (existing behavior)
- If `provider_id` is absent → pick `Provider.best_available.first` (highest-rated active provider)
- If no provider found either way → return 404

**`spec/requests/api/orders_spec.rb`** — 3 new specs covering auto-assignment:
- Assigns highest-rated active provider
- Ignores inactive providers
- Returns 404 when no active providers exist

All 37 specs pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..a06799f 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -18,7 +18,12 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
+      provider = if params[:provider_id].present?
+        Provider.find_by(id: params[:provider_id])
+      else
+        Provider.best_available.first
+      end
+
       return render_not_found unless provider
 
       result = Orders::CreateService.new(
diff --git a/affordance_order/app/models/provider.rb b/affordance_order/app/models/provider.rb
index caa04bd..f7036bb 100644
--- a/affordance_order/app/models/provider.rb
+++ b/affordance_order/app/models/provider.rb
@@ -12,6 +12,7 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :best_available, -> { active.order(rating: :desc) }
 
   private
 
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..db0ce0a 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -91,6 +91,47 @@
       post "/api/orders", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id (auto-assignment)" do
+      let(:params_without_provider) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "assigns the highest-rated active provider automatically" do
+        low_rated  = create(:provider, rating: 3.0, active: true)
+        high_rated = create(:provider, rating: 5.0, active: true)
+
+        post "/api/orders", params: params_without_provider, headers: auth_headers(client)
+
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "ignores inactive providers when auto-assigning" do
+        create(:provider, rating: 5.0, active: false)
+        active_provider = create(:provider, rating: 4.0, active: true)
+
+        post "/api/orders", params: params_without_provider, headers: auth_headers(client)
+
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(active_provider.id)
+      end
+
+      it "returns 404 when no active providers exist" do
+        Provider.update_all(active: false)
+
+        post "/api/orders", params: params_without_provider, headers: auth_headers(client)
+
+        expect(response).to have_http_status(:not_found)
+      end
+    end
   end
 
   describe "PATCH /api/orders/:id/confirm" do
```
