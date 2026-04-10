# Experiment: 04-bulk-booking
# App: order | Model: opus | Run: 2
# Branch: experiment/04-bulk-booking/order/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**New endpoint:** `POST /api/orders/bulk_create`

**What it does:**
- Creates 5 orders with the same provider, scheduled one week apart starting from the given `scheduled_at` time
- All orders share a `bulk_id` (UUID) for grouping
- Each order gets its own payment with a 10% fee
- Everything runs in a single database transaction — if any order fails validation, all are rolled back
- Provider is notified once with all order IDs

**Files changed:**
- `app/services/orders/bulk_create_service.rb` — new service handling the transactional bulk creation
- `app/controllers/api/orders_controller.rb` — new `bulk_create` action
- `config/routes.rb` — added collection route
- `app/models/order.rb` — added `by_bulk` scope
- `db/migrate/..._add_bulk_id_to_orders.rb` — adds indexed `bulk_id` column
- `spec/services/orders/bulk_create_service_spec.rb` — 8 service specs
- `spec/requests/api/orders_spec.rb` — 5 request specs

All 278 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..cb1ffba 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -34,6 +34,26 @@ def create
       end
     end
 
+    def bulk_create
+      client = current_client!
+      return if performed?
+
+      provider = Provider.find_by(id: params[:provider_id])
+      return render_not_found unless provider
+
+      result = Orders::BulkCreateService.new(
+        client: client,
+        provider: provider,
+        params: order_params
+      ).call
+
+      if result[:success]
+        render json: { bulk_id: result[:bulk_id], orders: result[:orders].map { |o| order_detail_json(o) } }, status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
@@ -125,7 +145,8 @@ def order_summary_json(order)
         amount_cents: order.amount_cents,
         currency: order.currency,
         client_id: order.client_id,
-        provider_id: order.provider_id
+        provider_id: order.provider_id,
+        bulk_id: order.bulk_id
       }
     end
 
@@ -145,6 +166,7 @@ def order_detail_json(order)
         completed_at: order.completed_at,
         client_id: order.client_id,
         provider_id: order.provider_id,
+        bulk_id: order.bulk_id,
         payment: order.payment ? {
           id: order.payment.id,
           status: order.payment.status,
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..517e5e7 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -25,6 +25,7 @@ class Order < ApplicationRecord
     scope = scope.where("scheduled_at <= ?", to) if to.present?
     scope
   }
+  scope :by_bulk, ->(bulk_id) { where(bulk_id: bulk_id) if bulk_id.present? }
   scope :sorted, -> { order(scheduled_at: :desc) }
 
   aasm column: :state do
diff --git a/affordance_order/app/services/orders/bulk_create_service.rb b/affordance_order/app/services/orders/bulk_create_service.rb
new file mode 100644
index 0000000..beab195
--- /dev/null
+++ b/affordance_order/app/services/orders/bulk_create_service.rb
@@ -0,0 +1,57 @@
+module Orders
+  class BulkCreateService
+    SESSIONS_COUNT = 5
+    INTERVAL = 1.week
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      bulk_id = SecureRandom.uuid
+      orders = []
+
+      Order.transaction do
+        SESSIONS_COUNT.times do |i|
+          base_time = @params[:scheduled_at].present? ? Time.zone.parse(@params[:scheduled_at].to_s) : nil
+          scheduled_at = base_time ? base_time + (i * INTERVAL) : nil
+
+          order = Order.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: scheduled_at,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB",
+            bulk_id: bulk_id
+          )
+
+          Payment.create!(
+            order: order,
+            amount_cents: order.amount_cents,
+            currency: order.currency,
+            fee_cents: calculate_fee(order.amount_cents),
+            status: "pending"
+          )
+
+          orders << order
+        end
+      end
+
+      NotificationService.notify(@provider, :bulk_order_created, order_ids: orders.map(&:id).join(","), bulk_id: bulk_id)
+      { success: true, orders: orders, bulk_id: bulk_id }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..e04e476 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :orders, only: [:index, :show, :create] do
+      collection do
+        post :bulk_create
+      end
       member do
         patch :confirm
         patch :start
diff --git a/affordance_order/db/migrate/20260407121333_add_bulk_id_to_orders.rb b/affordance_order/db/migrate/20260407121333_add_bulk_id_to_orders.rb
new file mode 100644
index 0000000..5418861
--- /dev/null
+++ b/affordance_order/db/migrate/20260407121333_add_bulk_id_to_orders.rb
@@ -0,0 +1,6 @@
+class AddBulkIdToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :bulk_id, :string
+    add_index :orders, :bulk_id
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..5e1b969 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_121333) do
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
+    t.integer "proposed_duration_minutes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
     t.string "state", default: "pending", null: false
     t.datetime "updated_at", null: false
+    t.index ["bulk_id"], name: "index_orders_on_bulk_id"
     t.index ["client_id"], name: "index_orders_on_client_id"
     t.index ["provider_id"], name: "index_orders_on_provider_id"
     t.index ["scheduled_at"], name: "index_orders_on_scheduled_at"
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..f8a9c22 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -93,6 +93,53 @@
     end
   end
 
+  describe "POST /api/orders/bulk_create" do
+    let(:order_params) do
+      {
+        provider_id: provider.id,
+        scheduled_at: 3.days.from_now.iso8601,
+        duration_minutes: 120,
+        amount_cents: 350_000,
+        currency: "RUB"
+      }
+    end
+
+    it "creates 5 orders in a single call" do
+      expect {
+        post "/api/orders/bulk_create", params: order_params, headers: auth_headers(client)
+      }.to change(Order, :count).by(5)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["orders"].size).to eq(5)
+      expect(body["bulk_id"]).to be_present
+    end
+
+    it "returns orders scheduled weekly" do
+      post "/api/orders/bulk_create", params: order_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body["orders"].map { |o| Time.zone.parse(o["scheduled_at"]) }.sort
+      (0...4).each do |i|
+        expect(times[i + 1] - times[i]).to be_within(1.second).of(1.week)
+      end
+    end
+
+    it "returns 403 for provider" do
+      post "/api/orders/bulk_create", params: order_params, headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for non-existent provider" do
+      post "/api/orders/bulk_create", params: order_params.merge(provider_id: 99999), headers: auth_headers(client)
+      expect(response).to have_http_status(:not_found)
+    end
+
+    it "returns validation errors for missing fields" do
+      post "/api/orders/bulk_create", params: { provider_id: provider.id }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/orders/:id/confirm" do
     let(:order) { create(:order, client: client, provider: provider) }
 
diff --git a/affordance_order/spec/services/orders/bulk_create_service_spec.rb b/affordance_order/spec/services/orders/bulk_create_service_spec.rb
new file mode 100644
index 0000000..e486920
--- /dev/null
+++ b/affordance_order/spec/services/orders/bulk_create_service_spec.rb
@@ -0,0 +1,71 @@
+require "rails_helper"
+
+RSpec.describe Orders::BulkCreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:start_time) { 3.days.from_now }
+  let(:valid_params) do
+    {
+      scheduled_at: start_time.iso8601,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 350_000,
+      currency: "RUB"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }
+
+  describe "#call" do
+    context "with valid params" do
+      it "creates 5 orders" do
+        expect { result }.to change(Order, :count).by(5)
+        expect(result[:success]).to be true
+        expect(result[:orders].size).to eq(5)
+      end
+
+      it "creates 5 payments" do
+        expect { result }.to change(Payment, :count).by(5)
+      end
+
+      it "assigns the same bulk_id to all orders" do
+        orders = result[:orders]
+        expect(orders.map(&:bulk_id).uniq.size).to eq(1)
+        expect(orders.first.bulk_id).to be_present
+      end
+
+      it "schedules orders one week apart" do
+        orders = result[:orders].sort_by(&:scheduled_at)
+        (0...4).each do |i|
+          diff = orders[i + 1].scheduled_at - orders[i].scheduled_at
+          expect(diff).to be_within(1.second).of(1.week)
+        end
+      end
+
+      it "returns the bulk_id" do
+        expect(result[:bulk_id]).to be_present
+        expect(result[:bulk_id]).to eq(result[:orders].first.bulk_id)
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=bulk_order_created")
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
+
+      it "returns errors and creates no orders" do
+        expect { result }.not_to change(Order, :count)
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "creates no payments on failure" do
+        expect { result }.not_to change(Payment, :count)
+      end
+    end
+  end
+end
```
