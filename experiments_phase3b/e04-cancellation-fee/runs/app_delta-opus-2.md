# Experiment: e04-cancellation-fee
# App: app_delta | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_delta/opus/run-2

---

## Claude Output

Here's a summary of what was implemented:

**Cancellation fee: 50% charge when canceled within 24 hours of scheduled time**

**Files changed:**

1. **Migration** — Added `cancellation_fee_cents` (integer, default 0) to `orders` table
2. **`app/models/order.rb`** — Added `late_cancellation?` (checks if `scheduled_at` is within 24 hours) and `cancellation_fee_amount` (50% of `amount_cents`)
3. **`app/services/payment_gateway.rb`** — Added `charge_cancellation_fee(payment, fee_cents)` that updates the payment amount to the fee and charges it
4. **`app/services/orders/cancel_service.rb`** — Split payment handling into two paths:
   - **Late cancellation**: charges 50% fee (adjusts existing payment or creates a new one)
   - **Normal cancellation**: full refund (existing behavior)
5. **`spec/services/orders/cancel_service_spec.rb`** — Added tests for late cancellation with held payment, charged payment, no payment with card, no payment without card, and verified no fee is charged for early cancellations

---

## Git Diff

```diff
diff --git a/app_delta/app/models/order.rb b/app_delta/app/models/order.rb
index 0fc2547..cf93930 100644
--- a/app_delta/app/models/order.rb
+++ b/app_delta/app/models/order.rb
@@ -28,6 +28,17 @@ class Order < ApplicationRecord
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
 
+  LATE_CANCELLATION_WINDOW = 24.hours
+  CANCELLATION_FEE_RATE = 0.5
+
+  def late_cancellation?
+    scheduled_at <= LATE_CANCELLATION_WINDOW.from_now
+  end
+
+  def cancellation_fee_amount
+    (amount_cents * CANCELLATION_FEE_RATE).to_i
+  end
+
   aasm column: :state do
     state :pending, initial: true
     state :confirmed
diff --git a/app_delta/app/services/orders/cancel_service.rb b/app_delta/app/services/orders/cancel_service.rb
index e04c1bc..8550e39 100644
--- a/app_delta/app/services/orders/cancel_service.rb
+++ b/app_delta/app/services/orders/cancel_service.rb
@@ -11,13 +11,17 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @order.cancel_reason = @reason
-      @order.cancel!
 
-      if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+      if @order.late_cancellation?
+        apply_cancellation_fee
+      else
+        refund_payment
       end
 
-      NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
+      @order.cancel!
+
+      NotificationService.notify(@order.provider, :order_canceled,
+        order_id: @order.id, cancellation_fee_cents: @order.cancellation_fee_cents)
       { success: true, order: @order }
     rescue AASM::InvalidTransition
       error("Cannot cancel order in #{@order.state} state")
@@ -25,6 +29,38 @@ def call
 
     private
 
+    def apply_cancellation_fee
+      fee = @order.cancellation_fee_amount
+      @order.cancellation_fee_cents = fee
+
+      if @order.payment && %w[held charged].include?(@order.payment.status)
+        PaymentGateway.charge_cancellation_fee(@order.payment, fee)
+      else
+        create_and_charge_fee_payment(fee)
+      end
+    end
+
+    def create_and_charge_fee_payment(fee)
+      card = @client.default_card
+      return unless card
+
+      payment = Payment.create!(
+        order: @order,
+        amount_cents: fee,
+        currency: @order.currency,
+        card: card,
+        status: "pending"
+      )
+      PaymentGateway.hold(payment)
+      PaymentGateway.charge(payment)
+    end
+
+    def refund_payment
+      if @order.payment && %w[held charged].include?(@order.payment.status)
+        PaymentGateway.refund(@order.payment)
+      end
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_delta/app/services/payment_gateway.rb b/app_delta/app/services/payment_gateway.rb
index 3530c85..dc539dc 100644
--- a/app_delta/app/services/payment_gateway.rb
+++ b/app_delta/app/services/payment_gateway.rb
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
+    return { success: false, error: "Payment not held or charged" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(amount_cents: fee_cents)
+    @payment.charge! if @payment.status == "held"
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_delta/db/migrate/20260409190215_add_cancellation_fee_cents_to_orders.rb b/app_delta/db/migrate/20260409190215_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..3a8ae3b
--- /dev/null
+++ b/app_delta/db/migrate/20260409190215_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index 7580f62..d81c9f8 100644
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
diff --git a/app_delta/spec/services/orders/cancel_service_spec.rb b/app_delta/spec/services/orders/cancel_service_spec.rb
index b0ced7f..3ac4bb2 100644
--- a/app_delta/spec/services/orders/cancel_service_spec.rb
+++ b/app_delta/spec/services/orders/cancel_service_spec.rb
@@ -20,7 +20,7 @@
       expect(confirmed_order.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when payment is held and cancellation is not late" do
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, order: order, card: card) }
 
@@ -53,5 +53,91 @@
       expect(result[:success]).to be false
       expect(result[:error]).to include("Cannot cancel order")
     end
+
+    context "late cancellation (within 24 hours of scheduled time)" do
+      let(:order) do
+        create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000)
+      end
+
+      it "sets the cancellation fee to 50% of the order amount" do
+        described_class.new(order: order, client: client, reason: "Emergency").call
+        expect(order.reload.cancellation_fee_cents).to eq(200_000)
+      end
+
+      context "when payment is held" do
+        let!(:card) { create(:card, :default, client: client) }
+        let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 400_000) }
+
+        it "charges the cancellation fee instead of refunding" do
+          described_class.new(order: order, client: client, reason: "Emergency").call
+          payment.reload
+          expect(payment.status).to eq("charged")
+          expect(payment.amount_cents).to eq(200_000)
+        end
+
+        it "logs the cancellation fee" do
+          described_class.new(order: order, client: client, reason: "Emergency").call
+          expect(read_payment_log).to include("action=cancellation_fee")
+          expect(read_payment_log).to include("fee=200000")
+        end
+      end
+
+      context "when payment is charged" do
+        let!(:card) { create(:card, :default, client: client) }
+        let!(:payment) { create(:payment, :charged, order: order, card: card, amount_cents: 400_000) }
+
+        it "reduces payment to the cancellation fee amount" do
+          described_class.new(order: order, client: client, reason: "Emergency").call
+          payment.reload
+          expect(payment.status).to eq("charged")
+          expect(payment.amount_cents).to eq(200_000)
+        end
+      end
+
+      context "when no payment exists but client has a card" do
+        let!(:card) { create(:card, :default, client: client) }
+
+        it "creates and charges a cancellation fee payment" do
+          expect {
+            described_class.new(order: order, client: client, reason: "Emergency").call
+          }.to change(Payment, :count).by(1)
+
+          payment = order.reload.payment
+          expect(payment.amount_cents).to eq(200_000)
+          expect(payment.status).to eq("charged")
+        end
+      end
+
+      context "when no payment exists and client has no card" do
+        it "still cancels successfully with fee recorded on order" do
+          result = described_class.new(order: order, client: client, reason: "Emergency").call
+          expect(result[:success]).to be true
+          expect(order.reload.cancellation_fee_cents).to eq(200_000)
+        end
+      end
+
+      it "includes cancellation fee in the notification" do
+        described_class.new(order: order, client: client, reason: "Emergency").call
+        expect(read_notification_log).to include("cancellation_fee_cents=200000")
+      end
+    end
+
+    context "cancellation more than 24 hours before scheduled time" do
+      let(:order) do
+        create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 400_000)
+      end
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 400_000) }
+
+      it "does not charge a cancellation fee" do
+        described_class.new(order: order, client: client, reason: "Changed my mind").call
+        expect(order.reload.cancellation_fee_cents).to eq(0)
+      end
+
+      it "fully refunds the payment" do
+        described_class.new(order: order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
   end
 end
```
