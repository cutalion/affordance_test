# Experiment: 06-cancellation-fee
# App: order | Model: sonnet | Run: 2
# Branch: experiment/06-cancellation-fee/order/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

- **Migration**: Added `cancellation_fee_cents` (integer, default 0) to `payments`
- **`Payment#partial_refund!`**: Sets status to `refunded` and records the fee amount
- **`PaymentGateway.partial_refund`**: Handles partial refund flow with logging
- **`CancelService`**: Detects late cancellation (`scheduled_at < 24.hours.from_now`) and applies 50% fee via `partial_refund`; early cancellations still get a full refund

---

## Git Diff

```diff
diff --git a/affordance_order/app/models/payment.rb b/affordance_order/app/models/payment.rb
index 5dec133..b6284e2 100644
--- a/affordance_order/app/models/payment.rb
+++ b/affordance_order/app/models/payment.rb
@@ -24,4 +24,8 @@ def charge!
   def refund!
     update!(status: "refunded", refunded_at: Time.current)
   end
+
+  def partial_refund!(fee_cents:)
+    update!(status: "refunded", refunded_at: Time.current, cancellation_fee_cents: fee_cents)
+  end
 end
diff --git a/affordance_order/app/services/orders/cancel_service.rb b/affordance_order/app/services/orders/cancel_service.rb
index e04c1bc..275f8dc 100644
--- a/affordance_order/app/services/orders/cancel_service.rb
+++ b/affordance_order/app/services/orders/cancel_service.rb
@@ -14,7 +14,12 @@ def call
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+        if late_cancellation?
+          fee_cents = (@order.payment.amount_cents * 0.5).to_i
+          PaymentGateway.partial_refund(@order.payment, fee_cents: fee_cents)
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
@@ -28,5 +33,9 @@ def call
     def error(message)
       { success: false, error: message }
     end
+
+    def late_cancellation?
+      @order.scheduled_at < 24.hours.from_now
+    end
   end
 end
diff --git a/affordance_order/app/services/payment_gateway.rb b/affordance_order/app/services/payment_gateway.rb
index 3530c85..a262375 100644
--- a/affordance_order/app/services/payment_gateway.rb
+++ b/affordance_order/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, fee_cents:)
+    new(payment).partial_refund(fee_cents: fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def partial_refund(fee_cents:)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.partial_refund!(fee_cents: fee_cents)
+    refund_amount = @payment.amount_cents - fee_cents
+    log("partial_refund", "payment_id=#{@payment.id} refund_amount=#{refund_amount} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_order/db/migrate/20260407000000_add_cancellation_fee_to_payments.rb b/affordance_order/db/migrate/20260407000000_add_cancellation_fee_to_payments.rb
new file mode 100644
index 0000000..fc975cb
--- /dev/null
+++ b/affordance_order/db/migrate/20260407000000_add_cancellation_fee_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, null: false, default: 0
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..721a312 100644
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
@@ -60,6 +64,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
@@ -105,7 +110,7 @@
 
   add_foreign_key "cards", "clients"
   add_foreign_key "orders", "clients"
-  add_foreign_key "orders", "providers"
+  add_foreign_key "orders", "providers", on_delete: :nullify
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "orders"
   add_foreign_key "reviews", "orders"
diff --git a/affordance_order/spec/services/orders/cancel_service_spec.rb b/affordance_order/spec/services/orders/cancel_service_spec.rb
index b0ced7f..42052d8 100644
--- a/affordance_order/spec/services/orders/cancel_service_spec.rb
+++ b/affordance_order/spec/services/orders/cancel_service_spec.rb
@@ -20,13 +20,27 @@
       expect(confirmed_order.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when payment is held and cancellation is more than 24h before scheduled time" do
+      let(:order) { create(:order, client: client, provider: provider, scheduled_at: 2.days.from_now) }
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, order: order, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment in full" do
         described_class.new(order: order, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(payment.reload.cancellation_fee_cents).to eq(0)
+      end
+    end
+
+    context "when payment is held and cancellation is less than 24h before scheduled time" do
+      let(:order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 350_000) }
+
+      it "charges a 50% cancellation fee" do
+        described_class.new(order: order, client: client, reason: "Last minute cancel").call
+        expect(payment.reload.status).to eq("refunded")
+        expect(payment.reload.cancellation_fee_cents).to eq(175_000)
       end
     end
 
```
