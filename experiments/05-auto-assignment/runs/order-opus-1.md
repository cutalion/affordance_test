# Experiment: 05-auto-assignment
# App: order | Model: opus | Run: 1
# Branch: experiment/05-auto-assignment/order/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**Provider model** (`app/models/provider.rb`): Added `available_at(time, duration)` scope that finds active providers with no overlapping orders, ordered by rating descending.

**Orders controller** (`app/controllers/api/orders_controller.rb`): `provider_id` is now optional in `POST /api/orders`. If omitted, auto-assignment kicks in.

**CreateService** (`app/services/orders/create_service.rb`): When no provider is passed, calls `assign_provider` to pick the highest-rated available one. Returns a clear error if no provider is available.

**Tests**: 10 new tests covering the scope, service auto-assignment (highest rated, skips inactive, skips busy, no-provider error), and request-level integration (auto-assign success, no-provider error). All 275 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..d57b56f 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -18,8 +18,10 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      if params[:provider_id].present?
+        provider = Provider.find_by(id: params[:provider_id])
+        return render_not_found unless provider
+      end
 
       result = Orders::CreateService.new(
         client: client,
diff --git a/affordance_order/app/models/provider.rb b/affordance_order/app/models/provider.rb
index caa04bd..84d557d 100644
--- a/affordance_order/app/models/provider.rb
+++ b/affordance_order/app/models/provider.rb
@@ -12,6 +12,15 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :available_at, ->(time, duration_minutes) {
+    new_end = time + duration_minutes.to_i.minutes
+    active.where.not(
+      id: Order.where(state: [:pending, :confirmed, :in_progress])
+              .where("scheduled_at < ? AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > ?",
+                     new_end, time)
+              .select(:provider_id)
+    ).order(rating: :desc)
+  }
 
   private
 
diff --git a/affordance_order/app/services/orders/create_service.rb b/affordance_order/app/services/orders/create_service.rb
index 156f0e3..43cffef 100644
--- a/affordance_order/app/services/orders/create_service.rb
+++ b/affordance_order/app/services/orders/create_service.rb
@@ -7,9 +7,12 @@ def initialize(client:, provider:, params:)
     end
 
     def call
+      provider = @provider || assign_provider
+      return { success: false, errors: no_provider_errors } unless provider
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
@@ -37,6 +40,20 @@ def call
 
     private
 
+    def assign_provider
+      scheduled_at = @params[:scheduled_at]
+      duration = @params[:duration_minutes]
+      return nil unless scheduled_at && duration
+
+      Provider.available_at(Time.zone.parse(scheduled_at.to_s), duration.to_i).first
+    end
+
+    def no_provider_errors
+      errors = ActiveModel::Errors.new(Order.new)
+      errors.add(:provider, "no available provider found")
+      errors
+    end
+
     def calculate_fee(amount_cents)
       (amount_cents * 0.1).to_i
     end
diff --git a/affordance_order/spec/models/provider_spec.rb b/affordance_order/spec/models/provider_spec.rb
index 0f8f5a6..fe1bf0e 100644
--- a/affordance_order/spec/models/provider_spec.rb
+++ b/affordance_order/spec/models/provider_spec.rb
@@ -59,6 +59,37 @@
     end
   end
 
+  describe ".available_at scope" do
+    let(:time) { 3.days.from_now }
+    let!(:free_provider) { create(:provider, rating: 4.5) }
+    let!(:busy_provider) { create(:provider, rating: 5.0) }
+    let!(:inactive_provider) { create(:provider, rating: 5.0, active: false) }
+
+    before do
+      create(:order, provider: busy_provider, scheduled_at: time, duration_minutes: 60)
+    end
+
+    it "excludes providers with overlapping orders" do
+      expect(Provider.available_at(time, 60)).to include(free_provider)
+      expect(Provider.available_at(time, 60)).not_to include(busy_provider)
+    end
+
+    it "excludes inactive providers" do
+      expect(Provider.available_at(time, 60)).not_to include(inactive_provider)
+    end
+
+    it "orders by rating descending" do
+      another = create(:provider, rating: 4.9)
+      result = Provider.available_at(time, 60)
+      expect(result.first).to eq(another)
+    end
+
+    it "includes providers whose orders do not overlap" do
+      non_overlapping_time = time + 2.hours
+      expect(Provider.available_at(non_overlapping_time, 60)).to include(busy_provider)
+    end
+  end
+
   describe "notification_preferences" do
     it "has default notification preferences" do
       provider = create(:provider)
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..78d974a 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -91,6 +91,31 @@
       post "/api/orders", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id (auto-assignment)" do
+      let!(:top_provider) { create(:provider, rating: 4.8) }
+      let(:auto_params) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "auto-assigns the highest-rated available provider" do
+        post "/api/orders", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(top_provider.id)
+      end
+
+      it "returns error when no providers are available" do
+        Provider.update_all(active: false)
+        post "/api/orders", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "PATCH /api/orders/:id/confirm" do
diff --git a/affordance_order/spec/services/orders/create_service_spec.rb b/affordance_order/spec/services/orders/create_service_spec.rb
index 140a104..cd12897 100644
--- a/affordance_order/spec/services/orders/create_service_spec.rb
+++ b/affordance_order/spec/services/orders/create_service_spec.rb
@@ -45,5 +45,36 @@
         expect(result[:errors]).to be_present
       end
     end
+
+    context "without a provider (auto-assignment)" do
+      subject(:result) { described_class.new(client: client, provider: nil, params: valid_params).call }
+
+      let!(:high_rated) { create(:provider, rating: 4.9) }
+      let!(:low_rated) { create(:provider, rating: 3.0) }
+      let!(:inactive) { create(:provider, rating: 5.0, active: false) }
+
+      it "assigns the highest-rated available provider" do
+        expect(result[:success]).to be true
+        expect(result[:order].provider).to eq(high_rated)
+      end
+
+      it "skips inactive providers" do
+        high_rated.update!(active: false)
+        expect(result[:order].provider).to eq(low_rated)
+      end
+
+      it "skips providers with conflicting orders" do
+        create(:order, provider: high_rated,
+               scheduled_at: valid_params[:scheduled_at],
+               duration_minutes: 60)
+        expect(result[:order].provider).to eq(low_rated)
+      end
+
+      it "returns error when no providers are available" do
+        Provider.update_all(active: false)
+        expect(result[:success]).to be false
+        expect(result[:errors][:provider]).to include("no available provider found")
+      end
+    end
   end
 end
```
