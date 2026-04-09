# Experiment: e04-cancellation-fee
# App: app_delta | Model: opus | Run: 3
# Branch: debt_experiment/e04-cancellation-fee/app_delta/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**Migration** — Added `cancellation_fee_cents` (default 0) to `orders` and `refund_amount_cents` to `payments`.

**`Orders::CancelService`** — When the order's `scheduled_at` is within 24 hours, sets `cancellation_fee_cents` to 50% of `amount_cents`. If a held/charged payment exists, does a partial refund (refunds only the non-fee portion). Orders canceled with >24h notice get a full refund as before.

**`PaymentGateway.partial_refund`** — New method that records the `refund_amount_cents` on the payment, marks it refunded, and logs the cancellation fee.

**5 new tests** covering:
- 50% fee charged when canceling within 24h
- Payment partially refunded (50%)
- Cancellation fee logged
- No fee when canceling >24h out
- Fee recorded even without a payment

---

## Git Diff

```diff
diff --git a/app_delta/app/services/orders/cancel_service.rb b/app_delta/app/services/orders/cancel_service.rb
index e04c1bc..f54dc56 100644
--- a/app_delta/app/services/orders/cancel_service.rb
+++ b/app_delta/app/services/orders/cancel_service.rb
@@ -11,10 +11,20 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @order.cancel_reason = @reason
+
+      if within_24_hours?
+        @order.cancellation_fee_cents = @order.amount_cents / 2
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
 
+    def within_24_hours?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_delta/app/services/payment_gateway.rb b/app_delta/app/services/payment_gateway.rb
index 3530c85..929ed4f 100644
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
+    @payment.update!(refund_amount_cents: refund_amount_cents)
+    @payment.refund!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{@payment.amount_cents - refund_amount_cents} refund=#{refund_amount_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_delta/db/migrate/20260409190619_add_cancellation_fee_and_refund_amount.rb b/app_delta/db/migrate/20260409190619_add_cancellation_fee_and_refund_amount.rb
new file mode 100644
index 0000000..6fd7c43
--- /dev/null
+++ b/app_delta/db/migrate/20260409190619_add_cancellation_fee_and_refund_amount.rb
@@ -0,0 +1,6 @@
+class AddCancellationFeeAndRefundAmount < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, default: 0, null: false unless column_exists?(:orders, :cancellation_fee_cents)
+    add_column :payments, :refund_amount_cents, :integer unless column_exists?(:payments, :refund_amount_cents)
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index 7580f62..59993df 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_140800) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_200000) do
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
@@ -89,6 +90,7 @@
     t.integer "fee_cents", default: 0, null: false
     t.datetime "held_at"
     t.integer "order_id", null: false
+    t.integer "refund_amount_cents"
     t.datetime "refunded_at"
     t.string "status", default: "pending", null: false
     t.datetime "updated_at", null: false
diff --git a/app_delta/spec/services/orders/cancel_service_spec.rb b/app_delta/spec/services/orders/cancel_service_spec.rb
index b0ced7f..70e8232 100644
--- a/app_delta/spec/services/orders/cancel_service_spec.rb
+++ b/app_delta/spec/services/orders/cancel_service_spec.rb
@@ -53,5 +53,58 @@
       expect(result[:success]).to be false
       expect(result[:error]).to include("Cannot cancel order")
     end
+
+    context "cancellation fee (within 24 hours of scheduled time)" do
+      let!(:card) { create(:card, :default, client: client) }
+
+      context "when canceled within 24 hours of scheduled_at" do
+        let(:order_soon) { create(:order, :confirmed, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000) }
+        let!(:payment) { create(:payment, :held, order: order_soon, card: card, amount_cents: 400_000) }
+
+        it "charges a 50% cancellation fee" do
+          result = described_class.new(order: order_soon, client: client, reason: "Emergency").call
+          expect(result[:success]).to be true
+          expect(order_soon.reload.cancellation_fee_cents).to eq(200_000)
+        end
+
+        it "partially refunds the payment (50%)" do
+          described_class.new(order: order_soon, client: client, reason: "Emergency").call
+          payment.reload
+          expect(payment.status).to eq("refunded")
+          expect(payment.refund_amount_cents).to eq(200_000)
+        end
+
+        it "logs the cancellation fee charge" do
+          described_class.new(order: order_soon, client: client, reason: "Emergency").call
+          expect(read_payment_log).to include("cancellation_fee")
+        end
+      end
+
+      context "when canceled more than 24 hours before scheduled_at" do
+        let(:order_later) { create(:order, :confirmed, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 400_000) }
+        let!(:payment) { create(:payment, :held, order: order_later, card: card, amount_cents: 400_000) }
+
+        it "does not charge a cancellation fee" do
+          result = described_class.new(order: order_later, client: client, reason: "Changed plans").call
+          expect(result[:success]).to be true
+          expect(order_later.reload.cancellation_fee_cents).to eq(0)
+        end
+
+        it "fully refunds the payment" do
+          described_class.new(order: order_later, client: client, reason: "Changed plans").call
+          expect(payment.reload.status).to eq("refunded")
+        end
+      end
+
+      context "when canceled within 24 hours but no payment exists" do
+        let(:order_soon_no_pay) { create(:order, :confirmed, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000) }
+
+        it "still records the cancellation fee on the order" do
+          result = described_class.new(order: order_soon_no_pay, client: client, reason: "Emergency").call
+          expect(result[:success]).to be true
+          expect(order_soon_no_pay.reload.cancellation_fee_cents).to eq(200_000)
+        end
+      end
+    end
   end
 end
```
