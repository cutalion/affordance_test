# Experiment: e04-cancellation-fee
# App: app_bravo | Model: opus | Run: 3
# Branch: debt_experiment/e04-cancellation-fee/app_bravo/opus/run-3

---

## Claude Output

All 132 tests pass. Here's a summary of the changes:

**`app/services/orders/cancel_service.rb`** — Added late cancellation detection. If the order's `scheduled_at` is within 24 hours, a 50% cancellation fee is charged via `partial_refund`; otherwise a full refund is issued as before.

**`app/services/payment_gateway.rb`** — Added `partial_refund` class/instance method that records the fee in `payment.fee_cents`, marks the payment as refunded, and logs the partial refund with fee details.

**`spec/services/orders/cancel_service_spec.rb`** — Added tests for late cancellation (within 24h: 50% fee charged) and early cancellation (more than 24h: full refund, no fee change).

**`spec/services/payment_gateway_spec.rb`** — Added tests for `partial_refund` (success, fee recording, logging, and failure for pending payments).

---

## Git Diff

```diff
diff --git a/app_bravo/app/services/orders/cancel_service.rb b/app_bravo/app/services/orders/cancel_service.rb
index e04c1bc..de45842 100644
--- a/app_bravo/app/services/orders/cancel_service.rb
+++ b/app_bravo/app/services/orders/cancel_service.rb
@@ -13,9 +13,7 @@ def call
       @order.cancel_reason = @reason
       @order.cancel!
 
-      if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
-      end
+      process_refund if @order.payment && %w[held charged].include?(@order.payment.status)
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
       { success: true, order: @order }
@@ -25,6 +23,20 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
+    def process_refund
+      if late_cancellation?
+        fee_cents = @order.amount_cents / 2
+        refund_cents = @order.amount_cents - fee_cents
+        PaymentGateway.partial_refund(@order.payment, refund_cents: refund_cents, fee_cents: fee_cents)
+      else
+        PaymentGateway.refund(@order.payment)
+      end
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_bravo/app/services/payment_gateway.rb b/app_bravo/app/services/payment_gateway.rb
index 3530c85..fd48d6c 100644
--- a/app_bravo/app/services/payment_gateway.rb
+++ b/app_bravo/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, refund_cents:, fee_cents:)
+    new(payment).partial_refund(refund_cents: refund_cents, fee_cents: fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def partial_refund(refund_cents:, fee_cents:)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(fee_cents: fee_cents)
+    @payment.refund!
+    log("partial_refund", "payment_id=#{@payment.id} refund=#{refund_cents} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_bravo/spec/services/orders/cancel_service_spec.rb b/app_bravo/spec/services/orders/cancel_service_spec.rb
index b0ced7f..1e855f7 100644
--- a/app_bravo/spec/services/orders/cancel_service_spec.rb
+++ b/app_bravo/spec/services/orders/cancel_service_spec.rb
@@ -30,6 +30,36 @@
       end
     end
 
+    context "when canceled within 24 hours of scheduled time" do
+      let(:soon_order) { create(:order, :confirmed, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: soon_order, card: card, amount_cents: 400_000) }
+
+      it "charges a 50% cancellation fee" do
+        described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("refunded")
+        expect(payment.fee_cents).to eq(200_000)
+      end
+
+      it "still cancels the order successfully" do
+        result = described_class.new(order: soon_order, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(soon_order.reload.state).to eq("canceled")
+      end
+    end
+
+    context "when canceled more than 24 hours before scheduled time" do
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: order.amount_cents) }
+
+      it "refunds fully without a cancellation fee" do
+        described_class.new(order: order, client: client, reason: "Changed my mind").call
+        payment.reload
+        expect(payment.status).to eq("refunded")
+        expect(payment.fee_cents).to eq(35_000) # unchanged from factory default
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(order: order, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=order_canceled")
diff --git a/app_bravo/spec/services/payment_gateway_spec.rb b/app_bravo/spec/services/payment_gateway_spec.rb
index 3f6ab9e..7251c8c 100644
--- a/app_bravo/spec/services/payment_gateway_spec.rb
+++ b/app_bravo/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,40 @@
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
+        result = PaymentGateway.partial_refund(payment, refund_cents: 200_000, fee_cents: 200_000)
+        expect(result[:success]).to be true
+      end
+
+      it "updates payment status to refunded" do
+        PaymentGateway.partial_refund(payment, refund_cents: 200_000, fee_cents: 200_000)
+        expect(payment.reload.status).to eq("refunded")
+      end
+
+      it "records the fee" do
+        PaymentGateway.partial_refund(payment, refund_cents: 200_000, fee_cents: 200_000)
+        expect(payment.reload.fee_cents).to eq(200_000)
+      end
+
+      it "writes to payment log" do
+        PaymentGateway.partial_refund(payment, refund_cents: 200_000, fee_cents: 200_000)
+        expect(read_payment_log).to include("[PAYMENT] action=partial_refund")
+        expect(read_payment_log).to include("fee=200000")
+      end
+    end
+
+    context "when payment is pending" do
+      it "returns failure" do
+        result = PaymentGateway.partial_refund(payment, refund_cents: 175_000, fee_cents: 175_000)
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Payment not chargeable")
+      end
+    end
+  end
 end
```
