# Experiment: e04-cancellation-fee
# App: app_delta | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_delta/opus/run-2

---

## Claude Output

All 177 tests pass. Here's what I implemented:

**Migration** — Added `cancellation_fee_cents` column to `orders` (default 0).

**`Orders::CancelService`** — Added a `late_cancellation?` check: if `scheduled_at` is within 24 hours, set `cancellation_fee_cents` to 50% of `amount_cents`. When a payment exists:
- Late cancellation: calls `partial_refund` — keeps the fee, refunds the rest, and marks payment as charged
- Normal cancellation: full refund as before

**`PaymentGateway`** — Added `partial_refund` method that reduces the payment amount by the refund portion and charges the remainder.

**Tests** — Added 4 new specs covering:
- Late cancellation stores the 50% fee on the order
- Late cancellation partially refunds (charges 50%, refunds 50%)
- Cancellation >24h out has no fee
- Cancellation >24h out gets a full refund

---

## Git Diff

```diff
diff --git a/app_delta/app/services/orders/cancel_service.rb b/app_delta/app/services/orders/cancel_service.rb
index e04c1bc..b7ef2a2 100644
--- a/app_delta/app/services/orders/cancel_service.rb
+++ b/app_delta/app/services/orders/cancel_service.rb
@@ -11,10 +11,20 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @order.cancel_reason = @reason
+
+      if late_cancellation?
+        @order.cancellation_fee_cents = (@order.amount_cents * 0.5).to_i
+      end
+
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+        if @order.cancellation_fee_cents > 0
+          refund_amount = @order.payment.amount_cents - @order.cancellation_fee_cents
+          PaymentGateway.partial_refund(@order.payment, refund_amount_cents: refund_amount)
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
@@ -25,6 +35,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_delta/app/services/payment_gateway.rb b/app_delta/app/services/payment_gateway.rb
index 3530c85..4dfd27f 100644
--- a/app_delta/app/services/payment_gateway.rb
+++ b/app_delta/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, refund_amount_cents:)
+    new(payment).partial_refund(refund_amount_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def partial_refund(refund_amount_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(amount_cents: @payment.amount_cents - refund_amount_cents)
+    @payment.charge!
+    log("partial_refund", "payment_id=#{@payment.id} refunded=#{refund_amount_cents} charged=#{@payment.amount_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_delta/db/migrate/20260410120000_add_cancellation_fee_cents_to_orders.rb b/app_delta/db/migrate/20260410120000_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..3a8ae3b
--- /dev/null
+++ b/app_delta/db/migrate/20260410120000_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index c5b443e..7c59fce 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -57,6 +57,7 @@
   create_table "orders", force: :cascade do |t|
     t.integer "amount_cents", null: false
     t.text "cancel_reason"
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "client_id", null: false
     t.datetime "completed_at"
     t.datetime "created_at", null: false
diff --git a/app_delta/spec/services/orders/cancel_service_spec.rb b/app_delta/spec/services/orders/cancel_service_spec.rb
index b0ced7f..30137ce 100644
--- a/app_delta/spec/services/orders/cancel_service_spec.rb
+++ b/app_delta/spec/services/orders/cancel_service_spec.rb
@@ -30,6 +30,41 @@
       end
     end
 
+    context "when canceled within 24 hours of scheduled time" do
+      let(:soon_order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 200_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: soon_order, card: card, amount_cents: 200_000) }
+
+      it "charges a 50% cancellation fee" do
+        result = described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(soon_order.reload.cancellation_fee_cents).to eq(100_000)
+      end
+
+      it "partially refunds the payment keeping the fee" do
+        described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        payment.reload
+        expect(payment.status).to eq("charged")
+        expect(payment.amount_cents).to eq(100_000)
+      end
+    end
+
+    context "when canceled more than 24 hours before scheduled time" do
+      let(:future_order) { create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 200_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: future_order, card: card, amount_cents: 200_000) }
+
+      it "does not charge a cancellation fee" do
+        described_class.new(order: future_order, client: client, reason: "Changed my mind").call
+        expect(future_order.reload.cancellation_fee_cents).to eq(0)
+      end
+
+      it "fully refunds the payment" do
+        described_class.new(order: future_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(order: order, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=order_canceled")
```
