# Experiment: 06-cancellation-fee
# App: request | Model: sonnet | Run: 3
# Branch: experiment/06-cancellation-fee/request/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**`CancelService`** — detects if `scheduled_at < 24.hours.from_now` and routes to fee vs refund:
- `< 24h` before: calls `PaymentGateway.charge_cancellation_fee`
- `>= 24h` before: calls `PaymentGateway.refund` (existing behavior)

**`PaymentGateway#charge_cancellation_fee`** — updates the payment amount to 50% (ceiling), then charges it, logging the action as `charge_cancellation_fee`.

All 293 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/services/payment_gateway.rb b/affordance_request/app/services/payment_gateway.rb
index be4203e..3b193a4 100644
--- a/affordance_request/app/services/payment_gateway.rb
+++ b/affordance_request/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.charge_cancellation_fee(payment)
+    new(payment).charge_cancellation_fee
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,16 @@ def refund
     { success: true }
   end
 
+  def charge_cancellation_fee
+    return { success: false, error: "Payment not held" } unless @payment.status == "held"
+
+    fee_amount = (@payment.amount_cents / 2.0).ceil
+    @payment.update!(amount_cents: fee_amount)
+    @payment.charge!
+    log("charge_cancellation_fee", "payment_id=#{@payment.id} amount=#{fee_amount} card=*#{@payment.card.last_four}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request/app/services/requests/cancel_service.rb b/affordance_request/app/services/requests/cancel_service.rb
index 546ae94..23b2fc8 100644
--- a/affordance_request/app/services/requests/cancel_service.rb
+++ b/affordance_request/app/services/requests/cancel_service.rb
@@ -14,7 +14,11 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if cancellation_fee_applies?
+          PaymentGateway.charge_cancellation_fee(@request.payment)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -25,6 +29,10 @@ def call
 
     private
 
+    def cancellation_fee_applies?
+      @request.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request/spec/services/requests/cancel_service_spec.rb b/affordance_request/spec/services/requests/cancel_service_spec.rb
index 98e0d2f..d46f509 100644
--- a/affordance_request/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request/spec/services/requests/cancel_service_spec.rb
@@ -30,6 +30,34 @@
       end
     end
 
+    context "when canceling less than 24 hours before scheduled time" do
+      let(:req) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: req, amount_cents: 350_000, card: card) }
+
+      it "charges a 50% cancellation fee instead of refunding" do
+        described_class.new(request: req, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.reload.amount_cents).to eq(175_000)
+      end
+
+      it "does not refund the payment" do
+        described_class.new(request: req, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).not_to eq("refunded")
+      end
+    end
+
+    context "when canceling 24 or more hours before scheduled time" do
+      let(:req) { create(:request, client: client, provider: provider, scheduled_at: 25.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: req, card: card) }
+
+      it "fully refunds the payment" do
+        described_class.new(request: req, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: req, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
