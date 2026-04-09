# Experiment: e04-cancellation-fee
# App: app_bravo | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_bravo/opus/run-2

---

## Claude Output

All 127 tests pass. Here's a summary of the changes:

**Migration**: Added `cancellation_fee_cents` column to `orders` (default 0).

**Order model** (`app/models/order.rb`):
- `late_cancellation?` — returns true if `scheduled_at` is within 24 hours
- `cancellation_fee` — returns 50% of `amount_cents`

**CancelService** (`app/services/orders/cancel_service.rb`):
- On late cancellation, sets `cancellation_fee_cents` on the order
- If a payment is held, reduces the payment amount to the fee and charges it (instead of refunding)
- If no late cancellation, refunds as before

**API response**: `cancellation_fee_cents` is included in the order detail JSON.

**Tests**: Added specs for late cancellation fee charging, fee amount correctness, and early cancellation still getting a full refund.

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/orders_controller.rb b/app_bravo/app/controllers/api/orders_controller.rb
index 2418afc..d2f04c5 100644
--- a/app_bravo/app/controllers/api/orders_controller.rb
+++ b/app_bravo/app/controllers/api/orders_controller.rb
@@ -140,6 +140,7 @@ def order_detail_json(order)
         amount_cents: order.amount_cents,
         currency: order.currency,
         cancel_reason: order.cancel_reason,
+        cancellation_fee_cents: order.cancellation_fee_cents,
         reject_reason: order.reject_reason,
         started_at: order.started_at,
         completed_at: order.completed_at,
diff --git a/app_bravo/app/models/order.rb b/app_bravo/app/models/order.rb
index 0fc2547..5fdc64c 100644
--- a/app_bravo/app/models/order.rb
+++ b/app_bravo/app/models/order.rb
@@ -62,4 +62,12 @@ class Order < ApplicationRecord
       transitions from: [:confirmed, :in_progress], to: :rejected
     end
   end
+
+  def late_cancellation?
+    scheduled_at <= 24.hours.from_now
+  end
+
+  def cancellation_fee
+    (amount_cents * 0.5).round
+  end
 end
diff --git a/app_bravo/app/services/orders/cancel_service.rb b/app_bravo/app/services/orders/cancel_service.rb
index e04c1bc..835a7d1 100644
--- a/app_bravo/app/services/orders/cancel_service.rb
+++ b/app_bravo/app/services/orders/cancel_service.rb
@@ -11,12 +11,15 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @order.cancel_reason = @reason
-      @order.cancel!
 
-      if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+      if @order.late_cancellation?
+        @order.cancellation_fee_cents = @order.cancellation_fee
       end
 
+      @order.cancel!
+
+      handle_payment_after_cancellation
+
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
       { success: true, order: @order }
     rescue AASM::InvalidTransition
@@ -25,6 +28,21 @@ def call
 
     private
 
+    def handle_payment_after_cancellation
+      return unless @order.payment
+      return unless %w[held charged].include?(@order.payment.status)
+
+      if @order.cancellation_fee_cents > 0
+        @order.payment.update!(
+          amount_cents: @order.cancellation_fee_cents,
+          fee_cents: @order.cancellation_fee_cents
+        )
+        PaymentGateway.charge(@order.payment) if @order.payment.status == "held"
+      else
+        PaymentGateway.refund(@order.payment)
+      end
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_bravo/db/migrate/20260409154202_add_cancellation_fee_to_orders.rb b/app_bravo/db/migrate/20260409154202_add_cancellation_fee_to_orders.rb
new file mode 100644
index 0000000..198ba55
--- /dev/null
+++ b/app_bravo/db/migrate/20260409154202_add_cancellation_fee_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index 667709c..0b9b305 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_075820) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_154202) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -39,6 +39,7 @@
   create_table "orders", force: :cascade do |t|
     t.integer "amount_cents", null: false
     t.text "cancel_reason"
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "client_id", null: false
     t.datetime "completed_at"
     t.datetime "created_at", null: false
@@ -62,6 +63,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
@@ -115,6 +117,8 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_reason"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.integer "recurring_booking_id"
     t.datetime "scheduled_at", null: false
diff --git a/app_bravo/spec/services/orders/cancel_service_spec.rb b/app_bravo/spec/services/orders/cancel_service_spec.rb
index b0ced7f..3fbcc6d 100644
--- a/app_bravo/spec/services/orders/cancel_service_spec.rb
+++ b/app_bravo/spec/services/orders/cancel_service_spec.rb
@@ -24,12 +24,44 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, order: order, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment when canceled early" do
         described_class.new(order: order, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
     end
 
+    context "when canceled within 24 hours of scheduled time (late cancellation)" do
+      let(:order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 100_000) }
+
+      it "sets a 50% cancellation fee" do
+        result = described_class.new(order: order, client: client, reason: "Last minute change").call
+        expect(result[:success]).to be true
+        expect(order.reload.cancellation_fee_cents).to eq(50_000)
+      end
+
+      context "with a held payment" do
+        let!(:card) { create(:card, :default, client: client) }
+        let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 100_000) }
+
+        it "charges the cancellation fee instead of refunding" do
+          described_class.new(order: order, client: client, reason: "Last minute change").call
+          payment.reload
+          expect(payment.status).to eq("charged")
+          expect(payment.amount_cents).to eq(50_000)
+        end
+      end
+    end
+
+    context "when canceled more than 24 hours before scheduled time" do
+      let(:order) { create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 100_000) }
+
+      it "does not charge a cancellation fee" do
+        result = described_class.new(order: order, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(order.reload.cancellation_fee_cents).to eq(0)
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(order: order, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=order_canceled")
```
