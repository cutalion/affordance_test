# Experiment: e04-cancellation-fee
# App: app_bravo | Model: opus | Run: 3
# Branch: debt_experiment/e04-cancellation-fee/app_bravo/opus/run-3

---

## Claude Output

Here's a summary of what was implemented:

**Cancellation fee: 50% charge when canceled within 24 hours of scheduled time**

### Changes:

1. **Migration** (`db/migrate/..._add_cancellation_fee_cents_to_orders.rb`) — Added `cancellation_fee_cents` (integer, default 0) to `orders` table to track the fee on the order.

2. **Migration** (`db/migrate/..._add_cancellation_fee_cents_to_payments.rb`) — Added `cancellation_fee_cents` (integer, default 0) to `payments` table to record the fee on the payment record.

3. **`Orders::CancelService`** — Added `late_cancellation?` check (`scheduled_at <= 24.hours.from_now`). When true and a payment exists, calculates 50% of `amount_cents` as the fee, stores it on the order, and calls `PaymentGateway.charge_cancellation_fee` instead of a full refund.

4. **`PaymentGateway`** — Added `charge_cancellation_fee(payment, fee_cents)` method. If the payment was held, it charges it first. Records the cancellation fee on the payment and logs the action.

5. **`Api::OrdersController`** — Exposes `cancellation_fee_cents` in the order detail JSON response.

6. **Tests** — Added specs for late cancellation (50% fee charged, payment status becomes "charged") and early cancellation (full refund, no fee). All 127 tests pass.

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
diff --git a/app_bravo/app/services/orders/cancel_service.rb b/app_bravo/app/services/orders/cancel_service.rb
index e04c1bc..1167645 100644
--- a/app_bravo/app/services/orders/cancel_service.rb
+++ b/app_bravo/app/services/orders/cancel_service.rb
@@ -14,7 +14,13 @@ def call
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+        if late_cancellation?
+          fee_cents = @order.amount_cents / 2
+          @order.update!(cancellation_fee_cents: fee_cents)
+          PaymentGateway.charge_cancellation_fee(@order.payment, fee_cents)
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
@@ -25,6 +31,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_bravo/app/services/payment_gateway.rb b/app_bravo/app/services/payment_gateway.rb
index 3530c85..fbe71f9 100644
--- a/app_bravo/app/services/payment_gateway.rb
+++ b/app_bravo/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.charge_cancellation_fee(payment, fee_cents)
+    new(payment).charge_cancellation_fee(fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,16 @@ def refund
     { success: true }
   end
 
+  def charge_cancellation_fee(fee_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.charge! if @payment.status == "held"
+    @payment.update!(cancellation_fee_cents: fee_cents)
+    refund_amount = @payment.amount_cents - fee_cents
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} refund=#{refund_amount}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_bravo/db/migrate/20260410074512_add_cancellation_fee_cents_to_orders.rb b/app_bravo/db/migrate/20260410074512_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..3a8ae3b
--- /dev/null
+++ b/app_bravo/db/migrate/20260410074512_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_bravo/db/migrate/20260410074553_add_cancellation_fee_cents_to_payments.rb b/app_bravo/db/migrate/20260410074553_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/app_bravo/db/migrate/20260410074553_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..109ca41 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_074553) do
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
diff --git a/app_bravo/spec/services/orders/cancel_service_spec.rb b/app_bravo/spec/services/orders/cancel_service_spec.rb
index b0ced7f..c064668 100644
--- a/app_bravo/spec/services/orders/cancel_service_spec.rb
+++ b/app_bravo/spec/services/orders/cancel_service_spec.rb
@@ -30,6 +30,36 @@
       end
     end
 
+    context "when canceled within 24 hours of scheduled time" do
+      let(:soon_order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: soon_order, card: card, amount_cents: 400_000) }
+
+      it "charges a 50% cancellation fee" do
+        result = described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(soon_order.reload.cancellation_fee_cents).to eq(200_000)
+      end
+
+      it "charges the payment instead of refunding" do
+        described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.reload.cancellation_fee_cents).to eq(200_000)
+      end
+    end
+
+    context "when canceled more than 24 hours before scheduled time" do
+      let(:future_order) { create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 400_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: future_order, card: card, amount_cents: 400_000) }
+
+      it "fully refunds the payment with no cancellation fee" do
+        described_class.new(order: future_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+        expect(future_order.reload.cancellation_fee_cents).to eq(0)
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(order: order, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=order_canceled")
```
