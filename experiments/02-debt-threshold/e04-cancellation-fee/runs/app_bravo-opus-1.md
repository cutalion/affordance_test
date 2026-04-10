# Experiment: e04-cancellation-fee
# App: app_bravo | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_bravo/opus/run-1

---

## Claude Output

All 138 tests pass. Here's a summary of the changes:

### Changes made

**Migration** — `db/migrate/20260410073839_add_cancellation_fee_cents_to_orders.rb`
- Adds `cancellation_fee_cents` integer column to orders (default: 0, not null)

**Order model** — `app/models/order.rb`
- `late_cancellation?` — returns true if `scheduled_at` is within 24 hours from now
- `cancellation_fee` — returns 50% of `amount_cents` for late cancellations, 0 otherwise

**CancelService** — `app/services/orders/cancel_service.rb`
- Calculates the cancellation fee before canceling
- Stores `cancellation_fee_cents` on the order
- Uses `PaymentGateway.partial_refund` when a fee applies (refunds amount minus fee)
- Falls back to full refund when no fee applies

**PaymentGateway** — `app/services/payment_gateway.rb`
- Added `partial_refund(payment, refund_amount_cents)` method that refunds the payment and logs the refunded/retained amounts

**API response** — `app/controllers/api/orders_controller.rb`
- Added `cancellation_fee_cents` to the order detail JSON

**Tests** — 12 new test cases covering:
- `Order#late_cancellation?` boundary conditions (within, at, beyond 24h)
- `Order#cancellation_fee` calculations including rounding
- `CancelService` fee charging and partial/full refund paths
- `PaymentGateway.partial_refund` success, logging, and failure cases

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
index 0fc2547..e476c44 100644
--- a/app_bravo/app/models/order.rb
+++ b/app_bravo/app/models/order.rb
@@ -28,6 +28,14 @@ class Order < ApplicationRecord
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
 
+  def late_cancellation?
+    scheduled_at <= 24.hours.from_now
+  end
+
+  def cancellation_fee
+    late_cancellation? ? (amount_cents * 0.5).to_i : 0
+  end
+
   aasm column: :state do
     state :pending, initial: true
     state :confirmed
diff --git a/app_bravo/app/services/orders/cancel_service.rb b/app_bravo/app/services/orders/cancel_service.rb
index e04c1bc..710d157 100644
--- a/app_bravo/app/services/orders/cancel_service.rb
+++ b/app_bravo/app/services/orders/cancel_service.rb
@@ -10,12 +10,12 @@ def call
       return error("Not your order") unless @order.client_id == @client.id
       return error("Cancel reason is required") if @reason.blank?
 
+      fee_cents = @order.cancellation_fee
+      @order.cancellation_fee_cents = fee_cents
       @order.cancel_reason = @reason
       @order.cancel!
 
-      if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
-      end
+      handle_payment_refund(fee_cents)
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
       { success: true, order: @order }
@@ -25,6 +25,18 @@ def call
 
     private
 
+    def handle_payment_refund(fee_cents)
+      return unless @order.payment
+      return unless %w[held charged].include?(@order.payment.status)
+
+      if fee_cents > 0
+        refund_amount = @order.amount_cents - fee_cents
+        PaymentGateway.partial_refund(@order.payment, refund_amount)
+      else
+        PaymentGateway.refund(@order.payment)
+      end
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_bravo/app/services/payment_gateway.rb b/app_bravo/app/services/payment_gateway.rb
index 3530c85..6eaea93 100644
--- a/app_bravo/app/services/payment_gateway.rb
+++ b/app_bravo/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, refund_amount_cents)
+    new(payment).partial_refund(refund_amount_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,14 @@ def refund
     { success: true }
   end
 
+  def partial_refund(refund_amount_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.refund!
+    log("partial_refund", "payment_id=#{@payment.id} refunded=#{refund_amount_cents} retained=#{@payment.amount_cents - refund_amount_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_bravo/db/migrate/20260410073839_add_cancellation_fee_cents_to_orders.rb b/app_bravo/db/migrate/20260410073839_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..42611df
--- /dev/null
+++ b/app_bravo/db/migrate/20260410073839_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, null: false, default: 0
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..7c72ebd 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_073839) do
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
diff --git a/app_bravo/spec/models/order_spec.rb b/app_bravo/spec/models/order_spec.rb
index 863befe..aee3df4 100644
--- a/app_bravo/spec/models/order_spec.rb
+++ b/app_bravo/spec/models/order_spec.rb
@@ -143,6 +143,40 @@
     end
   end
 
+  describe "#late_cancellation?" do
+    it "returns true when scheduled within 24 hours" do
+      order = build(:order, scheduled_at: 12.hours.from_now)
+      expect(order.late_cancellation?).to be true
+    end
+
+    it "returns true when scheduled exactly at 24 hours" do
+      order = build(:order, scheduled_at: 24.hours.from_now)
+      expect(order.late_cancellation?).to be true
+    end
+
+    it "returns false when scheduled more than 24 hours away" do
+      order = build(:order, scheduled_at: 25.hours.from_now)
+      expect(order.late_cancellation?).to be false
+    end
+  end
+
+  describe "#cancellation_fee" do
+    it "returns 50% of amount for late cancellation" do
+      order = build(:order, scheduled_at: 12.hours.from_now, amount_cents: 200_000)
+      expect(order.cancellation_fee).to eq(100_000)
+    end
+
+    it "returns 0 for non-late cancellation" do
+      order = build(:order, scheduled_at: 3.days.from_now, amount_cents: 200_000)
+      expect(order.cancellation_fee).to eq(0)
+    end
+
+    it "rounds down for odd amounts" do
+      order = build(:order, scheduled_at: 12.hours.from_now, amount_cents: 333)
+      expect(order.cancellation_fee).to eq(166)
+    end
+  end
+
   describe "scopes" do
     let!(:future_order) { create(:order, scheduled_at: 1.day.from_now) }
     let!(:past_order) { create(:order, scheduled_at: 1.day.ago) }
diff --git a/app_bravo/spec/services/orders/cancel_service_spec.rb b/app_bravo/spec/services/orders/cancel_service_spec.rb
index b0ced7f..84189eb 100644
--- a/app_bravo/spec/services/orders/cancel_service_spec.rb
+++ b/app_bravo/spec/services/orders/cancel_service_spec.rb
@@ -24,9 +24,43 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, order: order, card: card) }
 
-      it "refunds the held payment" do
+      it "fully refunds when canceled more than 24 hours before scheduled time" do
         described_class.new(order: order, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(read_payment_log).to include("action=refund")
+        expect(read_payment_log).not_to include("action=partial_refund")
+      end
+
+      context "when canceled within 24 hours of scheduled time" do
+        let(:order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000) }
+        let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 400_000) }
+
+        it "partially refunds keeping 50% as cancellation fee" do
+          described_class.new(order: order, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("refunded")
+          expect(read_payment_log).to include("action=partial_refund")
+          expect(read_payment_log).to include("retained=200000")
+        end
+      end
+    end
+
+    context "cancellation fee" do
+      it "charges no fee when canceled more than 24 hours before scheduled time" do
+        order = create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 200_000)
+        described_class.new(order: order, client: client, reason: "Changed my mind").call
+        expect(order.reload.cancellation_fee_cents).to eq(0)
+      end
+
+      it "charges 50% fee when canceled within 24 hours of scheduled time" do
+        order = create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 200_000)
+        described_class.new(order: order, client: client, reason: "Changed my mind").call
+        expect(order.reload.cancellation_fee_cents).to eq(100_000)
+      end
+
+      it "charges 50% fee when canceled exactly at 24 hours before scheduled time" do
+        order = create(:order, client: client, provider: provider, scheduled_at: 24.hours.from_now, amount_cents: 200_000)
+        described_class.new(order: order, client: client, reason: "Changed my mind").call
+        expect(order.reload.cancellation_fee_cents).to eq(100_000)
       end
     end
 
diff --git a/app_bravo/spec/services/payment_gateway_spec.rb b/app_bravo/spec/services/payment_gateway_spec.rb
index 3f6ab9e..5bf21d8 100644
--- a/app_bravo/spec/services/payment_gateway_spec.rb
+++ b/app_bravo/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,36 @@
       end
     end
   end
+
+  describe ".partial_refund" do
+    context "when payment is held" do
+      let(:card) { create(:card, :default, client: client) }
+      let(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 400_000) }
+
+      it "returns success" do
+        result = PaymentGateway.partial_refund(payment, 200_000)
+        expect(result[:success]).to be true
+      end
+
+      it "updates payment status to refunded" do
+        PaymentGateway.partial_refund(payment, 200_000)
+        expect(payment.reload.status).to eq("refunded")
+      end
+
+      it "logs partial refund with retained amount" do
+        PaymentGateway.partial_refund(payment, 200_000)
+        expect(read_payment_log).to include("[PAYMENT] action=partial_refund")
+        expect(read_payment_log).to include("refunded=200000")
+        expect(read_payment_log).to include("retained=200000")
+      end
+    end
+
+    context "when payment is pending" do
+      it "returns failure" do
+        result = PaymentGateway.partial_refund(payment, 100_000)
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Payment not chargeable")
+      end
+    end
+  end
 end
```
