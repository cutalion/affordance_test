# Experiment: 05-auto-assignment
# App: order | Model: opus | Run: 3
# Branch: experiment/05-auto-assignment/order/opus/run-3

---

## Claude Output

Done. Here's a summary of what was implemented:

**Provider model** (`app/models/provider.rb`): Added `available_at(scheduled_at, duration_minutes)` scope that finds active providers with no overlapping orders (pending/confirmed/in_progress), ordered by rating descending.

**CreateService** (`app/services/orders/create_service.rb`): When no provider is passed, calls `auto_assign_provider` which uses the new scope to pick the highest-rated available provider. Returns an error if none is found.

**OrdersController** (`app/controllers/api/orders_controller.rb`): Made `provider_id` optional — if omitted, the service handles auto-assignment. Updated error handling to support both validation errors and plain string errors.

**Tests**: 4 new specs covering: assigns highest-rated provider, skips busy providers, skips inactive providers, and returns error when no provider is available.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..0819846 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -18,8 +18,11 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = nil
+      if params[:provider_id].present?
+        provider = Provider.find_by(id: params[:provider_id])
+        return render_not_found unless provider
+      end
 
       result = Orders::CreateService.new(
         client: client,
@@ -30,7 +33,9 @@ def create
       if result[:success]
         render json: order_detail_json(result[:order]), status: :created
       else
-        render_unprocessable(result[:errors].full_messages)
+        errors = result[:errors]
+        messages = errors.respond_to?(:full_messages) ? errors.full_messages : Array(errors)
+        render_unprocessable(messages)
       end
     end
 
diff --git a/affordance_order/app/models/provider.rb b/affordance_order/app/models/provider.rb
index caa04bd..89c7e9e 100644
--- a/affordance_order/app/models/provider.rb
+++ b/affordance_order/app/models/provider.rb
@@ -12,6 +12,17 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :available_at, ->(scheduled_at, duration_minutes) {
+    end_time = scheduled_at + duration_minutes.to_i.minutes
+    active.where.not(
+      id: Order.where(state: %w[pending confirmed in_progress])
+               .where(
+                 "scheduled_at < ? AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > ?",
+                 end_time, scheduled_at
+               )
+               .select(:provider_id)
+    ).order(rating: :desc)
+  }
 
   private
 
diff --git a/affordance_order/app/services/orders/create_service.rb b/affordance_order/app/services/orders/create_service.rb
index 156f0e3..00e55f0 100644
--- a/affordance_order/app/services/orders/create_service.rb
+++ b/affordance_order/app/services/orders/create_service.rb
@@ -7,9 +7,12 @@ def initialize(client:, provider:, params:)
     end
 
     def call
+      provider = @provider || auto_assign_provider
+      return { success: false, errors: ["No available provider found"] } unless provider
+
       order = Order.new(
         client: @client,
-        provider: @provider,
+        provider: provider,
         scheduled_at: @params[:scheduled_at],
         duration_minutes: @params[:duration_minutes],
         location: @params[:location],
@@ -29,7 +32,7 @@ def call
         )
       end
 
-      NotificationService.notify(@provider, :order_created, order_id: order.id)
+      NotificationService.notify(provider, :order_created, order_id: order.id)
       { success: true, order: order }
     rescue ActiveRecord::RecordInvalid => e
       { success: false, errors: e.record.errors }
@@ -37,6 +40,14 @@ def call
 
     private
 
+    def auto_assign_provider
+      scheduled_at = Time.zone.parse(@params[:scheduled_at].to_s)
+      duration_minutes = @params[:duration_minutes].to_i
+      return nil unless scheduled_at && duration_minutes > 0
+
+      Provider.available_at(scheduled_at, duration_minutes).first
+    end
+
     def calculate_fee(amount_cents)
       (amount_cents * 0.1).to_i
     end
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..606a4cc 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -91,6 +91,56 @@
       post "/api/orders", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "auto-assignment when provider_id is omitted" do
+      let(:auto_params) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "assigns the highest-rated available provider" do
+        low_rated = create(:provider, rating: 3.0)
+        high_rated = create(:provider, rating: 5.0)
+
+        post "/api/orders", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "skips providers who have overlapping orders" do
+        busy_provider = create(:provider, rating: 5.0)
+        free_provider = create(:provider, rating: 4.0)
+        create(:order, provider: busy_provider, client: client,
+               scheduled_at: 3.days.from_now, duration_minutes: 180)
+
+        post "/api/orders", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(free_provider.id)
+      end
+
+      it "skips inactive providers" do
+        create(:provider, rating: 5.0, active: false)
+        active_provider = create(:provider, rating: 3.0)
+
+        post "/api/orders", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(active_provider.id)
+      end
+
+      it "returns error when no provider is available" do
+        Provider.update_all(active: false)
+
+        post "/api/orders", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "PATCH /api/orders/:id/confirm" do
```
