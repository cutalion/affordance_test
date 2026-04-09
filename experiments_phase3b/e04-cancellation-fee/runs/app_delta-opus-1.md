# Experiment: e04-cancellation-fee
# App: app_delta | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_delta/opus/run-1

---

## Claude Output

All 178 tests pass. Here's a summary of the changes:

**Migration** — Added `cancellation_fee_cents` (integer, default 0) to `orders` table.

**`Orders::CancelService`** — When a booking is canceled within 24 hours of `scheduled_at`, sets `cancellation_fee_cents` to 50% of `amount_cents`. If a payment exists (held/charged), calls `PaymentGateway.charge_cancellation_fee` instead of a full refund. Cancellations more than 24 hours out still get a full refund with no fee.

**`PaymentGateway`** — Added `charge_cancellation_fee(payment, fee_cents:)` class/instance method that marks the payment as refunded and logs the fee amount and partial refund amount.

**Tests** — 5 new test cases covering: fee charged within 24h, payment refunded with fee, cancellation fee logged, no fee when >24h out, and fee recorded even without a payment.

---

## Git Diff

```diff
diff --git a/app_delta/app/services/orders/cancel_service.rb b/app_delta/app/services/orders/cancel_service.rb
index e04c1bc..0eb9e75 100644
--- a/app_delta/app/services/orders/cancel_service.rb
+++ b/app_delta/app/services/orders/cancel_service.rb
@@ -11,12 +11,15 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @order.cancel_reason = @reason
-      @order.cancel!
 
-      if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+      if late_cancellation?
+        @order.cancellation_fee_cents = @order.amount_cents / 2
       end
 
+      @order.cancel!
+
+      process_payment_refund
+
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
       { success: true, order: @order }
     rescue AASM::InvalidTransition
@@ -25,6 +28,20 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
+    def process_payment_refund
+      return unless @order.payment && %w[held charged].include?(@order.payment.status)
+
+      if @order.cancellation_fee_cents > 0
+        PaymentGateway.charge_cancellation_fee(@order.payment, fee_cents: @order.cancellation_fee_cents)
+      else
+        PaymentGateway.refund(@order.payment)
+      end
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_delta/app/services/payment_gateway.rb b/app_delta/app/services/payment_gateway.rb
index 3530c85..9ce1a1b 100644
--- a/app_delta/app/services/payment_gateway.rb
+++ b/app_delta/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.charge_cancellation_fee(payment, fee_cents:)
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
+    refund_amount = @payment.amount_cents - fee_cents
+    @payment.refund!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} refund=#{refund_amount}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_delta/db/migrate/20260409185948_add_cancellation_fee_cents_to_orders.rb b/app_delta/db/migrate/20260409185948_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..3a8ae3b
--- /dev/null
+++ b/app_delta/db/migrate/20260409185948_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index 7580f62..58db0df 100644
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
@@ -137,6 +138,9 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_reason"
+    t.datetime "proposed_at"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
diff --git a/app_delta/spec/services/orders/cancel_service_spec.rb b/app_delta/spec/services/orders/cancel_service_spec.rb
index b0ced7f..c42a6bc 100644
--- a/app_delta/spec/services/orders/cancel_service_spec.rb
+++ b/app_delta/spec/services/orders/cancel_service_spec.rb
@@ -4,7 +4,7 @@
   let(:client) { create(:client) }
   let(:other_client) { create(:client) }
   let(:provider) { create(:provider) }
-  let(:order) { create(:order, client: client, provider: provider) }
+  let(:order) { create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now) }
 
   describe "#call" do
     it "cancels a pending order" do
@@ -24,9 +24,50 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, order: order, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment fully when canceled early" do
         described_class.new(order: order, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(order.reload.cancellation_fee_cents).to eq(0)
+      end
+    end
+
+    context "cancellation fee" do
+      let(:order_soon) { create(:order, :confirmed, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: order_soon, card: card, amount_cents: 400_000) }
+
+      it "charges 50% fee when canceled within 24 hours of scheduled time" do
+        result = described_class.new(order: order_soon, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(order_soon.reload.cancellation_fee_cents).to eq(200_000)
+      end
+
+      it "refunds the payment with cancellation fee applied" do
+        described_class.new(order: order_soon, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+
+      it "logs the cancellation fee" do
+        described_class.new(order: order_soon, client: client, reason: "Emergency").call
+        log = File.read(PaymentGateway::LOG_PATH.call)
+        expect(log).to include("action=cancellation_fee")
+        expect(log).to include("fee=200000")
+        expect(log).to include("refund=200000")
+      end
+
+      it "does not charge fee when canceled more than 24 hours before" do
+        order_far = create(:order, :confirmed, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 400_000)
+        payment_far = create(:payment, :held, order: order_far, card: card, amount_cents: 400_000)
+        described_class.new(order: order_far, client: client, reason: "Changed plans").call
+        expect(order_far.reload.cancellation_fee_cents).to eq(0)
+        expect(payment_far.reload.status).to eq("refunded")
+      end
+
+      it "still records fee when there is no payment" do
+        order_no_pay = create(:order, :confirmed, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000)
+        result = described_class.new(order: order_no_pay, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(order_no_pay.reload.cancellation_fee_cents).to eq(200_000)
       end
     end
 
```
