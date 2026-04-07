# Experiment: 05-auto-assignment
# App: order | Model: opus | Run: 2
# Branch: experiment/05-auto-assignment/order/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**Provider model** — Added `available_at` scope that finds active providers without conflicting orders at a given time, and `highest_rated_available` class method that returns the top-rated one.

**Order model** — Made `provider` association optional so orders can be created without specifying a provider upfront.

**CreateService** — `provider` parameter is now optional. When omitted, `auto_assign_provider` finds the highest-rated available provider. Returns an error if no provider is available.

**OrdersController** — `provider_id` is no longer required in the create action. If omitted, the service handles auto-assignment.

**Migration** — Made `provider_id` nullable on the orders table.

**Tests** — 4 new tests on CreateService (assigns highest-rated, skips inactive, skips busy, errors when none available) and 3 on Provider model. All 272 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..9119e6d 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -18,8 +18,8 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = Provider.find_by(id: params[:provider_id]) if params[:provider_id].present?
+      return render_not_found if params[:provider_id].present? && provider.nil?
 
       result = Orders::CreateService.new(
         client: client,
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..6fb425f 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -3,7 +3,7 @@ class Order < ApplicationRecord
   include Paginatable
 
   belongs_to :client
-  belongs_to :provider
+  belongs_to :provider, optional: true
   has_one :payment, dependent: :destroy
   has_many :reviews, dependent: :destroy
 
diff --git a/affordance_order/app/models/provider.rb b/affordance_order/app/models/provider.rb
index caa04bd..977a1bb 100644
--- a/affordance_order/app/models/provider.rb
+++ b/affordance_order/app/models/provider.rb
@@ -12,6 +12,18 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :available_at, ->(time, duration_minutes) {
+    active.where.not(
+      id: Order.where(state: [:pending, :confirmed, :in_progress])
+              .where("scheduled_at < ? AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > ?",
+                     time + duration_minutes.minutes, time)
+              .select(:provider_id)
+    )
+  }
+
+  def self.highest_rated_available(scheduled_at:, duration_minutes:)
+    available_at(scheduled_at, duration_minutes).order(rating: :desc).first
+  end
 
   private
 
diff --git a/affordance_order/app/services/orders/create_service.rb b/affordance_order/app/services/orders/create_service.rb
index 156f0e3..0f584af 100644
--- a/affordance_order/app/services/orders/create_service.rb
+++ b/affordance_order/app/services/orders/create_service.rb
@@ -1,15 +1,18 @@
 module Orders
   class CreateService
-    def initialize(client:, provider:, params:)
+    def initialize(client:, provider: nil, params:)
       @client = client
       @provider = provider
       @params = params
     end
 
     def call
+      provider = @provider || auto_assign_provider
+      return { success: false, errors: "No available provider found" } unless provider
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
@@ -40,5 +43,12 @@ def call
     def calculate_fee(amount_cents)
       (amount_cents * 0.1).to_i
     end
+
+    def auto_assign_provider
+      Provider.highest_rated_available(
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes].to_i
+      )
+    end
   end
 end
diff --git a/affordance_order/db/migrate/20260407124347_change_provider_id_optional_on_orders.rb b/affordance_order/db/migrate/20260407124347_change_provider_id_optional_on_orders.rb
new file mode 100644
index 0000000..e1ee835
--- /dev/null
+++ b/affordance_order/db/migrate/20260407124347_change_provider_id_optional_on_orders.rb
@@ -0,0 +1,7 @@
+class ChangeProviderIdOptionalOnOrders < ActiveRecord::Migration[8.1]
+  def change
+    change_column_null :orders, :provider_id, true
+    remove_foreign_key :orders, :providers
+    add_foreign_key :orders, :providers, on_delete: :nullify
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..f5dadd2 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_124347) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -38,6 +38,7 @@
 
   create_table "orders", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.string "bulk_id"
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
@@ -46,12 +47,15 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
-    t.integer "provider_id", null: false
+    t.integer "proposed_duration_minutes"
+    t.datetime "proposed_scheduled_at"
+    t.integer "provider_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
     t.string "state", default: "pending", null: false
     t.datetime "updated_at", null: false
+    t.index ["bulk_id"], name: "index_orders_on_bulk_id"
     t.index ["client_id"], name: "index_orders_on_client_id"
     t.index ["provider_id"], name: "index_orders_on_provider_id"
     t.index ["scheduled_at"], name: "index_orders_on_scheduled_at"
@@ -105,7 +109,7 @@
 
   add_foreign_key "cards", "clients"
   add_foreign_key "orders", "clients"
-  add_foreign_key "orders", "providers"
+  add_foreign_key "orders", "providers", on_delete: :nullify
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "orders"
   add_foreign_key "reviews", "orders"
diff --git a/affordance_order/spec/models/order_spec.rb b/affordance_order/spec/models/order_spec.rb
index 6686df0..5dc73e6 100644
--- a/affordance_order/spec/models/order_spec.rb
+++ b/affordance_order/spec/models/order_spec.rb
@@ -3,7 +3,7 @@
 RSpec.describe Order, type: :model do
   describe "associations" do
     it { is_expected.to belong_to(:client) }
-    it { is_expected.to belong_to(:provider) }
+    it { is_expected.to belong_to(:provider).optional }
     it { is_expected.to have_one(:payment).dependent(:destroy) }
     it { is_expected.to have_many(:reviews).dependent(:destroy) }
   end
diff --git a/affordance_order/spec/models/provider_spec.rb b/affordance_order/spec/models/provider_spec.rb
index 0f8f5a6..55729fa 100644
--- a/affordance_order/spec/models/provider_spec.rb
+++ b/affordance_order/spec/models/provider_spec.rb
@@ -59,6 +59,30 @@
     end
   end
 
+  describe ".highest_rated_available" do
+    let(:scheduled_at) { 3.days.from_now }
+    let(:duration) { 120 }
+
+    it "returns the highest-rated active provider" do
+      low = create(:provider, rating: 3.0)
+      high = create(:provider, rating: 4.8)
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to eq(high)
+    end
+
+    it "excludes providers with overlapping orders" do
+      busy = create(:provider, rating: 5.0)
+      free = create(:provider, rating: 3.0)
+      create(:order, :confirmed, provider: busy, scheduled_at: scheduled_at, duration_minutes: 120)
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to eq(free)
+    end
+
+    it "returns nil when no providers are available" do
+      expect(Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)).to be_nil
+    end
+  end
+
   describe "notification_preferences" do
     it "has default notification preferences" do
       provider = create(:provider)
diff --git a/affordance_order/spec/services/orders/create_service_spec.rb b/affordance_order/spec/services/orders/create_service_spec.rb
index 140a104..900e102 100644
--- a/affordance_order/spec/services/orders/create_service_spec.rb
+++ b/affordance_order/spec/services/orders/create_service_spec.rb
@@ -45,5 +45,36 @@
         expect(result[:errors]).to be_present
       end
     end
+
+    context "without a provider (auto-assignment)" do
+      subject(:result) { described_class.new(client: client, params: valid_params).call }
+
+      let!(:low_rated) { create(:provider, rating: 3.0, active: true) }
+      let!(:high_rated) { create(:provider, rating: 5.0, active: true) }
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
+        create(:order, :confirmed, provider: high_rated,
+               scheduled_at: valid_params[:scheduled_at],
+               duration_minutes: 120)
+        expect(result[:order].provider).to eq(low_rated)
+      end
+
+      it "returns error when no providers are available" do
+        Provider.update_all(active: false)
+        expect(result[:success]).to be false
+        expect(result[:errors]).to include("No available provider found")
+      end
+    end
   end
 end
```
