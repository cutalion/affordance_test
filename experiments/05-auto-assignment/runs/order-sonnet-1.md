# Experiment: 05-auto-assignment
# App: order | Model: sonnet | Run: 1
# Branch: experiment/05-auto-assignment/order/sonnet/run-1

---

## Claude Output

Done. Here's what was changed:

**`app/models/provider.rb`** — added `by_rating` scope that orders by `rating desc`

**`app/controllers/api/orders_controller.rb`** — updated `create` to:
- Use the explicit `provider_id` when provided (existing behavior, 404 if not found)
- Fall back to `Provider.active.by_rating.first` when `provider_id` is absent
- Return 422 `"No available provider found"` if no active providers exist

**`spec/requests/api/orders_spec.rb`** — two new specs:
- Verifies the highest-rated active provider is assigned
- Verifies 422 is returned when no active providers are available

All 24 specs pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..3738129 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
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
+        Provider.active.by_rating.first
+      end
+
+      return render_unprocessable(["No available provider found"]) unless provider
 
       result = Orders::CreateService.new(
         client: client,
diff --git a/affordance_order/app/models/provider.rb b/affordance_order/app/models/provider.rb
index caa04bd..7512e4e 100644
--- a/affordance_order/app/models/provider.rb
+++ b/affordance_order/app/models/provider.rb
@@ -12,6 +12,7 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :by_rating, -> { order(rating: :desc) }
 
   private
 
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..5993f39 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -91,6 +91,36 @@
       post "/api/orders", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id (auto-assignment)" do
+      let(:base_params) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "assigns the highest-rated active provider" do
+        low_rated  = create(:provider, rating: 3.0)
+        high_rated = create(:provider, rating: 5.0)
+
+        post "/api/orders", params: base_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "returns 422 when no active providers exist" do
+        Provider.update_all(active: false)
+
+        post "/api/orders", params: base_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+        body = JSON.parse(response.body)
+        expect(body["errors"]).to include("No available provider found")
+      end
+    end
   end
 
   describe "PATCH /api/orders/:id/confirm" do
```
