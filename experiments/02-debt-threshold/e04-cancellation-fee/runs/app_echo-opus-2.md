# Experiment: e04-cancellation-fee
# App: app_echo | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_echo/opus/run-2

---

## Claude Output

Implementation complete. Here's a summary of what was done:

**Changes made to 4 files:**

1. **`app/services/requests/cancel_service.rb`** — Added late cancellation check. If `scheduled_at` is within 24 hours, charges 50% of `amount_cents` as a cancellation fee via partial refund. Otherwise, full refund as before. Returns `cancellation_fee_cents` in the result when a fee is charged.

2. **`app/services/payment_gateway.rb`** — Added `partial_refund(payment, fee_cents:)` class/instance method. Records the fee on the payment's `fee_cents` column, marks the payment as refunded, and logs the action.

3. **`spec/services/requests/cancel_service_spec.rb`** — Added tests for late cancellation (within 24h: charges 50% fee, refunds, returns fee in result) and early cancellation (>24h: no fee, full refund).

4. **`spec/services/payment_gateway_spec.rb`** — Added tests for `.partial_refund` (success with held payment, records fee, marks refunded, logs; failure with pending payment).

**Key assumptions:**
- "Within 24 hours" means `scheduled_at` is ≤ 24 hours from now at the time of cancellation
- The fee is 50% of `request.amount_cents` (integer division)
- The existing `fee_cents` column on `payments` is used to store the cancellation fee — no migration needed
- The payment is marked as `refunded` (the net refund is `amount_cents - fee_cents`)

---

## Git Diff

```diff
diff --git a/app_echo/app/services/payment_gateway.rb b/app_echo/app/services/payment_gateway.rb
index be4203e..d0bfae7 100644
--- a/app_echo/app/services/payment_gateway.rb
+++ b/app_echo/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, fee_cents:)
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
+    @payment.update!(fee_cents: fee_cents)
+    @payment.refund!
+    log("partial_refund", "payment_id=#{@payment.id} amount=#{@payment.amount_cents} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_echo/app/services/requests/cancel_service.rb b/app_echo/app/services/requests/cancel_service.rb
index 546ae94..f65f09c 100644
--- a/app_echo/app/services/requests/cancel_service.rb
+++ b/app_echo/app/services/requests/cancel_service.rb
@@ -13,18 +13,31 @@ def call
       @request.cancel_reason = @reason
       @request.cancel!
 
+      cancellation_fee_cents = 0
+
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if late_cancellation?
+          cancellation_fee_cents = @request.amount_cents / 2
+          PaymentGateway.partial_refund(@request.payment, fee_cents: cancellation_fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
-      { success: true, request: @request }
+      result = { success: true, request: @request }
+      result[:cancellation_fee_cents] = cancellation_fee_cents if cancellation_fee_cents > 0
+      result
     rescue AASM::InvalidTransition
       error("Cannot cancel request in #{@request.state} state")
     end
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_echo/spec/services/payment_gateway_spec.rb b/app_echo/spec/services/payment_gateway_spec.rb
index 8b2e52c..22c42b3 100644
--- a/app_echo/spec/services/payment_gateway_spec.rb
+++ b/app_echo/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,40 @@
       end
     end
   end
+
+  describe ".partial_refund" do
+    context "when payment is held" do
+      let(:card) { create(:card, :default, client: client) }
+      let(:payment) { create(:payment, :held, request: request, card: card, amount_cents: 400_000) }
+
+      it "returns success" do
+        result = PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+        expect(result[:success]).to be true
+      end
+
+      it "records the fee on the payment" do
+        PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+        expect(payment.reload.fee_cents).to eq(200_000)
+      end
+
+      it "marks the payment as refunded" do
+        PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+        expect(payment.reload.status).to eq("refunded")
+      end
+
+      it "writes to payment log" do
+        PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+        expect(read_payment_log).to include("[PAYMENT] action=partial_refund")
+        expect(read_payment_log).to include("fee=200000")
+      end
+    end
+
+    context "when payment is pending" do
+      it "returns failure" do
+        result = PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Payment not chargeable")
+      end
+    end
+  end
 end
diff --git a/app_echo/spec/services/requests/cancel_service_spec.rb b/app_echo/spec/services/requests/cancel_service_spec.rb
index 5458786..9354f27 100644
--- a/app_echo/spec/services/requests/cancel_service_spec.rb
+++ b/app_echo/spec/services/requests/cancel_service_spec.rb
@@ -30,6 +30,43 @@
       end
     end
 
+    context "when canceled within 24 hours of scheduled time" do
+      let(:soon_request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 400_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: soon_request, card: card, amount_cents: 400_000) }
+
+      it "charges a 50% cancellation fee" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(payment.reload.fee_cents).to eq(200_000)
+      end
+
+      it "refunds the payment" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+
+      it "returns the cancellation fee in the result" do
+        result = described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(result[:cancellation_fee_cents]).to eq(200_000)
+      end
+    end
+
+    context "when canceled more than 24 hours before scheduled time" do
+      let(:future_request) { create(:request, client: client, provider: provider, scheduled_at: 3.days.from_now, amount_cents: 400_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: future_request, card: card, amount_cents: 400_000) }
+
+      it "does not charge a cancellation fee" do
+        described_class.new(request: future_request, client: client, reason: "Changed my mind").call
+        expect(payment.reload.fee_cents).to eq(35_000) # unchanged factory default
+      end
+
+      it "fully refunds the payment" do
+        described_class.new(request: future_request, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: request, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
