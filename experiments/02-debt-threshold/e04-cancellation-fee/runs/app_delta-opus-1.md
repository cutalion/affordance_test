# Experiment: e04-cancellation-fee
# App: app_delta | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_delta/opus/run-1

---

## Claude Output

All 182 tests pass. Here's a summary of what was implemented:

**Cancellation fee: 50% charge when canceling within 24 hours of scheduled time**

**Changes:**

1. **Migration** (`db/migrate/20260408140809_add_cancellation_fee_cents_to_orders.rb`) — Added `cancellation_fee_cents` column to orders table.

2. **`Orders::CancelService`** — When a booking is canceled within 24 hours of `scheduled_at`, a 50% cancellation fee is calculated and stored on the order. If a payment exists, a partial refund is issued (refunding only the non-fee portion). Cancellations more than 24 hours out still get a full refund with no fee.

3. **`PaymentGateway`** — Added `.partial_refund(payment, refund_amount_cents)` for issuing partial refunds with proper logging.

4. **`Payment` model** — Added `partial_refund!(refund_amount_cents)` which marks the payment as refunded and reduces `amount_cents` to reflect the retained fee.

5. **Orders API response** — `cancellation_fee_cents` is now included in the order detail JSON.

6. **Tests** — Added specs for cancellation fee calculation (within/beyond 24h), partial refund behavior, and payment gateway partial refund logging.

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/orders_controller.rb b/app_delta/app/controllers/api/orders_controller.rb
index 2418afc..d2f04c5 100644
--- a/app_delta/app/controllers/api/orders_controller.rb
+++ b/app_delta/app/controllers/api/orders_controller.rb
@@ -140,6 +140,7 @@ def order_detail_json(order)
         amount_cents: order.amount_cents,
         currency: order.currency,
         cancel_reason: order.cancel_reason,
+        cancellation_fee_cents: order.cancellation_fee_cents,
         reject_reason: order.reject_reason,
         started_at: order.started_at,
         completed_at: order.completed_at,
diff --git a/app_delta/app/models/payment.rb b/app_delta/app/models/payment.rb
index 5dec133..f7c8841 100644
--- a/app_delta/app/models/payment.rb
+++ b/app_delta/app/models/payment.rb
@@ -24,4 +24,12 @@ def charge!
   def refund!
     update!(status: "refunded", refunded_at: Time.current)
   end
+
+  def partial_refund!(refund_amount_cents)
+    update!(
+      status: "refunded",
+      amount_cents: amount_cents - refund_amount_cents,
+      refunded_at: Time.current
+    )
+  end
 end
diff --git a/app_delta/app/services/orders/cancel_service.rb b/app_delta/app/services/orders/cancel_service.rb
index e04c1bc..f3861da 100644
--- a/app_delta/app/services/orders/cancel_service.rb
+++ b/app_delta/app/services/orders/cancel_service.rb
@@ -11,10 +11,19 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @order.cancel_reason = @reason
+
+      fee_cents = calculate_cancellation_fee
+      @order.cancellation_fee_cents = fee_cents
+
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+        if fee_cents > 0
+          refund_amount = @order.payment.amount_cents - fee_cents
+          PaymentGateway.partial_refund(@order.payment, refund_amount)
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
@@ -25,6 +34,13 @@ def call
 
     private
 
+    def calculate_cancellation_fee
+      return 0 unless @order.scheduled_at.present?
+      return 0 if @order.scheduled_at > 24.hours.from_now
+
+      (@order.amount_cents * 0.5).to_i
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_delta/app/services/payment_gateway.rb b/app_delta/app/services/payment_gateway.rb
index 3530c85..c0365d2 100644
--- a/app_delta/app/services/payment_gateway.rb
+++ b/app_delta/app/services/payment_gateway.rb
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
@@ -43,6 +47,16 @@ def refund
     { success: true }
   end
 
+  def partial_refund(refund_amount_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+    return { success: false, error: "Invalid refund amount" } if refund_amount_cents <= 0 || refund_amount_cents > @payment.amount_cents
+
+    retained = @payment.amount_cents - refund_amount_cents
+    @payment.partial_refund!(refund_amount_cents)
+    log("partial_refund", "payment_id=#{@payment.id} refunded=#{refund_amount_cents} retained=#{retained}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_delta/db/migrate/20260408140809_add_cancellation_fee_cents_to_orders.rb b/app_delta/db/migrate/20260408140809_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..42611df
--- /dev/null
+++ b/app_delta/db/migrate/20260408140809_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, null: false, default: 0
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index c5b443e..c121847 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_08_140809) do
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
index b0ced7f..b93d14e 100644
--- a/app_delta/spec/services/orders/cancel_service_spec.rb
+++ b/app_delta/spec/services/orders/cancel_service_spec.rb
@@ -30,6 +30,40 @@
       end
     end
 
+    context "cancellation fee" do
+      let(:order_soon) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 200_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: order_soon, card: card, amount_cents: 200_000) }
+
+      it "charges 50% fee when canceled within 24 hours of scheduled time" do
+        result = described_class.new(order: order_soon, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(order_soon.reload.cancellation_fee_cents).to eq(100_000)
+      end
+
+      it "partially refunds the payment when fee applies" do
+        described_class.new(order: order_soon, client: client, reason: "Emergency").call
+        payment.reload
+        expect(payment.status).to eq("refunded")
+        expect(payment.amount_cents).to eq(100_000)
+      end
+
+      it "does not charge a fee when canceled more than 24 hours before" do
+        order_later = create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 200_000)
+        result = described_class.new(order: order_later, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(order_later.reload.cancellation_fee_cents).to eq(0)
+      end
+
+      it "fully refunds the payment when no fee applies" do
+        order_later = create(:order, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 200_000)
+        later_payment = create(:payment, :held, order: order_later, card: card, amount_cents: 200_000)
+        described_class.new(order: order_later, client: client, reason: "Changed my mind").call
+        expect(later_payment.reload.status).to eq("refunded")
+        expect(later_payment.amount_cents).to eq(200_000)
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(order: order, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=order_canceled")
diff --git a/app_delta/spec/services/payment_gateway_spec.rb b/app_delta/spec/services/payment_gateway_spec.rb
index 3f6ab9e..1d7f627 100644
--- a/app_delta/spec/services/payment_gateway_spec.rb
+++ b/app_delta/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,41 @@
       end
     end
   end
+
+  describe ".partial_refund" do
+    context "when payment is held" do
+      let(:card) { create(:card, :default, client: client) }
+      let(:payment) { create(:payment, :held, order: order, card: card, amount_cents: 200_000) }
+
+      it "returns success" do
+        result = PaymentGateway.partial_refund(payment, 100_000)
+        expect(result[:success]).to be true
+      end
+
+      it "updates payment status to refunded" do
+        PaymentGateway.partial_refund(payment, 100_000)
+        expect(payment.reload.status).to eq("refunded")
+      end
+
+      it "reduces the payment amount by the refunded amount" do
+        PaymentGateway.partial_refund(payment, 100_000)
+        expect(payment.reload.amount_cents).to eq(100_000)
+      end
+
+      it "writes to payment log" do
+        PaymentGateway.partial_refund(payment, 100_000)
+        expect(read_payment_log).to include("[PAYMENT] action=partial_refund")
+        expect(read_payment_log).to include("refunded=100000")
+        expect(read_payment_log).to include("retained=100000")
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
