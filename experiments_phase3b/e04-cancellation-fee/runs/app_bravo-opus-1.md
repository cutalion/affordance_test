# Experiment: e04-cancellation-fee
# App: app_bravo | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_bravo/opus/run-1

---

## Claude Output

All 132 tests pass. Here's a summary of the changes:

**Migration** — Added `cancellation_fee_cents` column to `payments` table (default: 0).

**`Orders::CancelService`** — Extracted payment refund logic into `process_payment_refund`. If the order's `scheduled_at` is within 24 hours from now (`late_cancellation?`), it charges a 50% cancellation fee instead of issuing a full refund.

**`PaymentGateway`** — Added `charge_cancellation_fee(payment, fee_cents)` method that records the fee on the payment, charges it, and logs the action.

**Tests** — Added specs for:
- Late cancellation (within 24h): verifies 50% fee is charged and logged
- Early cancellation (>24h): verifies full refund with no fee
- `PaymentGateway.charge_cancellation_fee`: success, status update, fee recording, logging, and failure cases

---

## Git Diff

```diff
diff --git a/app_bravo/app/services/orders/cancel_service.rb b/app_bravo/app/services/orders/cancel_service.rb
index e04c1bc..1fa9a74 100644
--- a/app_bravo/app/services/orders/cancel_service.rb
+++ b/app_bravo/app/services/orders/cancel_service.rb
@@ -13,9 +13,7 @@ def call
       @order.cancel_reason = @reason
       @order.cancel!
 
-      if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
-      end
+      process_payment_refund
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
       { success: true, order: @order }
@@ -25,6 +23,22 @@ def call
 
     private
 
+    def process_payment_refund
+      payment = @order.payment
+      return unless payment && %w[held charged].include?(payment.status)
+
+      if late_cancellation?
+        fee_cents = @order.amount_cents / 2
+        PaymentGateway.charge_cancellation_fee(payment, fee_cents)
+      else
+        PaymentGateway.refund(payment)
+      end
+    end
+
+    def late_cancellation?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_bravo/app/services/payment_gateway.rb b/app_bravo/app/services/payment_gateway.rb
index 3530c85..20b3852 100644
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
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def charge_cancellation_fee(fee_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(cancellation_fee_cents: fee_cents)
+    @payment.charge!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} original_amount=#{@payment.amount_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_bravo/db/migrate/20260409153951_add_cancellation_fee_cents_to_payments.rb b/app_bravo/db/migrate/20260409153951_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/app_bravo/db/migrate/20260409153951_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index 667709c..186d20b 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_075820) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_153951) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -62,6 +62,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
@@ -115,6 +116,8 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_reason"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.integer "recurring_booking_id"
     t.datetime "scheduled_at", null: false
diff --git a/app_bravo/spec/services/orders/cancel_service_spec.rb b/app_bravo/spec/services/orders/cancel_service_spec.rb
index b0ced7f..914403d 100644
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
+        described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.cancellation_fee_cents).to eq(200_000)
+      end
+
+      it "logs the cancellation fee" do
+        described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        expect(read_payment_log).to include("action=cancellation_fee")
+        expect(read_payment_log).to include("fee=200000")
+      end
+    end
+
+    context "when canceled more than 24 hours before scheduled time" do
+      let(:later_order) { create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 400_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: later_order, card: card, amount_cents: 400_000) }
+
+      it "fully refunds the payment" do
+        described_class.new(order: later_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+        expect(payment.cancellation_fee_cents).to eq(0)
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(order: order, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=order_canceled")
diff --git a/app_bravo/spec/services/payment_gateway_spec.rb b/app_bravo/spec/services/payment_gateway_spec.rb
index 3f6ab9e..136bc3c 100644
--- a/app_bravo/spec/services/payment_gateway_spec.rb
+++ b/app_bravo/spec/services/payment_gateway_spec.rb
@@ -72,6 +72,42 @@
     end
   end
 
+  describe ".charge_cancellation_fee" do
+    context "when payment is held" do
+      let(:card) { create(:card, :default, client: client) }
+      let(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 400_000) }
+
+      it "returns success" do
+        result = PaymentGateway.charge_cancellation_fee(payment, 200_000)
+        expect(result[:success]).to be true
+      end
+
+      it "updates payment status to charged" do
+        PaymentGateway.charge_cancellation_fee(payment, 200_000)
+        expect(payment.reload.status).to eq("charged")
+      end
+
+      it "records the cancellation fee amount" do
+        PaymentGateway.charge_cancellation_fee(payment, 200_000)
+        expect(payment.reload.cancellation_fee_cents).to eq(200_000)
+      end
+
+      it "writes to payment log" do
+        PaymentGateway.charge_cancellation_fee(payment, 200_000)
+        expect(read_payment_log).to include("[PAYMENT] action=cancellation_fee")
+        expect(read_payment_log).to include("fee=200000")
+      end
+    end
+
+    context "when payment is pending" do
+      it "returns failure" do
+        result = PaymentGateway.charge_cancellation_fee(payment, 175_000)
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Payment not chargeable")
+      end
+    end
+  end
+
   describe ".refund" do
     context "when payment is charged" do
       let(:card) { create(:card, :default, client: client) }
```
