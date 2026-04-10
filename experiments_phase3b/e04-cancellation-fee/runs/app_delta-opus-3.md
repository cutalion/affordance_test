# Experiment: e04-cancellation-fee
# App: app_delta | Model: opus | Run: 3
# Branch: debt_experiment/e04-cancellation-fee/app_delta/opus/run-3

---

## Claude Output

All 178 tests pass. Here's a summary of the changes:

**Migration** — Added `cancellation_fee_cents` (integer, default 0) to the `orders` table.

**`Orders::CancelService`** — Added `late_cancellation?` check: if `scheduled_at` is within 24 hours, sets `cancellation_fee_cents` to 50% of `amount_cents`. Late cancellations trigger a partial refund (retaining the fee); early cancellations still get a full refund. The cancellation fee is included in the provider notification payload.

**`PaymentGateway`** — Added `partial_refund(fee_cents)` method that refunds the payment minus the retained fee, with appropriate logging.

**Tests** — Added specs for both late cancellation (within 24h: fee charged, partial refund, notification includes fee) and early cancellation (more than 24h: no fee, full refund).

---

## Git Diff

```diff
diff --git a/app_delta/app/services/orders/cancel_service.rb b/app_delta/app/services/orders/cancel_service.rb
index e04c1bc..81179ce 100644
--- a/app_delta/app/services/orders/cancel_service.rb
+++ b/app_delta/app/services/orders/cancel_service.rb
@@ -11,13 +11,24 @@ def call
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
+          PaymentGateway.partial_refund(@order.payment, @order.cancellation_fee_cents)
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
-      NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
+      notification_payload = { order_id: @order.id }
+      notification_payload[:cancellation_fee_cents] = @order.cancellation_fee_cents if @order.cancellation_fee_cents > 0
+      NotificationService.notify(@order.provider, :order_canceled, notification_payload)
       { success: true, order: @order }
     rescue AASM::InvalidTransition
       error("Cannot cancel order in #{@order.state} state")
@@ -25,6 +36,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_delta/app/services/payment_gateway.rb b/app_delta/app/services/payment_gateway.rb
index 3530c85..2b750b3 100644
--- a/app_delta/app/services/payment_gateway.rb
+++ b/app_delta/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, fee_cents)
+    new(payment).partial_refund(fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def partial_refund(fee_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    refund_amount = @payment.amount_cents - fee_cents
+    @payment.refund!
+    log("partial_refund", "payment_id=#{@payment.id} refunded=#{refund_amount} fee_retained=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_delta/db/migrate/20260410120000_add_cancellation_fee_cents_to_orders.rb b/app_delta/db/migrate/20260410120000_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..45b2844
--- /dev/null
+++ b/app_delta/db/migrate/20260410120000_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[7.1]
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
index b0ced7f..a52f6c6 100644
--- a/app_delta/spec/services/orders/cancel_service_spec.rb
+++ b/app_delta/spec/services/orders/cancel_service_spec.rb
@@ -53,5 +53,58 @@
       expect(result[:success]).to be false
       expect(result[:error]).to include("Cannot cancel order")
     end
+
+    context "cancellation fee" do
+      context "when canceled within 24 hours of scheduled time" do
+        let(:order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 100_000) }
+
+        it "charges a 50% cancellation fee" do
+          result = described_class.new(order: order, client: client, reason: "Last minute change").call
+          expect(result[:success]).to be true
+          expect(order.reload.cancellation_fee_cents).to eq(50_000)
+        end
+
+        context "with a held payment" do
+          let!(:card) { create(:card, :default, client: client) }
+          let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 100_000) }
+
+          it "does a partial refund retaining the fee" do
+            described_class.new(order: order, client: client, reason: "Last minute change").call
+            expect(payment.reload.status).to eq("refunded")
+            log = File.read(PaymentGateway::LOG_PATH.call)
+            expect(log).to include("partial_refund")
+            expect(log).to include("fee_retained=50000")
+          end
+        end
+
+        it "includes cancellation fee in notification" do
+          described_class.new(order: order, client: client, reason: "Last minute change").call
+          expect(read_notification_log).to include("cancellation_fee_cents=50000")
+        end
+      end
+
+      context "when canceled more than 24 hours before scheduled time" do
+        let(:order) { create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 100_000) }
+
+        it "does not charge a cancellation fee" do
+          result = described_class.new(order: order, client: client, reason: "Changed my mind").call
+          expect(result[:success]).to be true
+          expect(order.reload.cancellation_fee_cents).to eq(0)
+        end
+
+        context "with a held payment" do
+          let!(:card) { create(:card, :default, client: client) }
+          let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 100_000) }
+
+          it "does a full refund" do
+            described_class.new(order: order, client: client, reason: "Changed my mind").call
+            expect(payment.reload.status).to eq("refunded")
+            log = File.read(PaymentGateway::LOG_PATH.call)
+            expect(log).to include("action=refund")
+            expect(log).not_to include("partial_refund")
+          end
+        end
+      end
+    end
   end
 end
```
