# Experiment: 06-cancellation-fee
# App: request | Model: opus | Run: 1
# Branch: experiment/06-cancellation-fee/request/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

- **`CancelService`** — checks if `scheduled_at < 24.hours.from_now` (late cancellation). If so, charges a 50% fee via `refund_with_fee`; otherwise does a full refund as before.
- **`PaymentGateway.refund_with_fee`** — new method that sets `fee_cents` on the payment before refunding, and logs the fee amount.
- **`PaymentGateway.refund`** — now explicitly resets `fee_cents` to 0 for full refunds.
- **API response** — `fee_cents` is now included in the payment JSON.
- **Tests** — cancel service tests cover both early (full refund) and late (50% fee) scenarios; gateway tests cover `refund_with_fee`.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..90f4ae8 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -177,6 +177,7 @@ def request_detail_json(req)
           id: req.payment.id,
           status: req.payment.status,
           amount_cents: req.payment.amount_cents,
+          fee_cents: req.payment.fee_cents,
           currency: req.payment.currency
         } : nil,
         created_at: req.created_at,
diff --git a/affordance_request/app/services/payment_gateway.rb b/affordance_request/app/services/payment_gateway.rb
index be4203e..a5ae5a8 100644
--- a/affordance_request/app/services/payment_gateway.rb
+++ b/affordance_request/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.refund_with_fee(payment, fee_cents:)
+    new(payment).refund_with_fee(fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -38,11 +42,21 @@ def charge
   def refund
     return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
 
+    @payment.update!(fee_cents: 0)
     @payment.refund!
     log("refund", "payment_id=#{@payment.id} amount=#{@payment.amount_cents}")
     { success: true }
   end
 
+  def refund_with_fee(fee_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(fee_cents: fee_cents)
+    @payment.refund!
+    log("refund_with_fee", "payment_id=#{@payment.id} amount=#{@payment.amount_cents} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request/app/services/requests/cancel_service.rb b/affordance_request/app/services/requests/cancel_service.rb
index 546ae94..224be7c 100644
--- a/affordance_request/app/services/requests/cancel_service.rb
+++ b/affordance_request/app/services/requests/cancel_service.rb
@@ -14,7 +14,12 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if late_cancellation?
+          fee_cents = (@request.amount_cents * 0.5).to_i
+          PaymentGateway.refund_with_fee(@request.payment, fee_cents: fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -25,6 +30,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request/spec/services/payment_gateway_spec.rb b/affordance_request/spec/services/payment_gateway_spec.rb
index 6ad18d4..f460d52 100644
--- a/affordance_request/spec/services/payment_gateway_spec.rb
+++ b/affordance_request/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,37 @@
       end
     end
   end
+
+  describe ".refund_with_fee" do
+    context "when payment is held" do
+      let(:card) { create(:card, :default, client: client) }
+      let(:payment) { create(:payment, :held, request: req, card: card, amount_cents: 350_000) }
+
+      it "returns success" do
+        result = PaymentGateway.refund_with_fee(payment, fee_cents: 175_000)
+        expect(result[:success]).to be true
+      end
+
+      it "sets the fee and refunds" do
+        PaymentGateway.refund_with_fee(payment, fee_cents: 175_000)
+        payment.reload
+        expect(payment.status).to eq("refunded")
+        expect(payment.fee_cents).to eq(175_000)
+      end
+
+      it "writes to payment log" do
+        PaymentGateway.refund_with_fee(payment, fee_cents: 175_000)
+        expect(read_payment_log).to include("[PAYMENT] action=refund_with_fee")
+        expect(read_payment_log).to include("fee=175000")
+      end
+    end
+
+    context "when payment is pending" do
+      it "returns failure" do
+        result = PaymentGateway.refund_with_fee(payment, fee_cents: 175_000)
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Payment not chargeable")
+      end
+    end
+  end
 end
diff --git a/affordance_request/spec/services/requests/cancel_service_spec.rb b/affordance_request/spec/services/requests/cancel_service_spec.rb
index 98e0d2f..1703c6b 100644
--- a/affordance_request/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request/spec/services/requests/cancel_service_spec.rb
@@ -24,9 +24,25 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: req, card: card) }
 
-      it "refunds the held payment" do
-        described_class.new(request: req, client: client, reason: "Changed my mind").call
-        expect(payment.reload.status).to eq("refunded")
+      context "when cancelling 24+ hours before scheduled time" do
+        before { req.update!(scheduled_at: 48.hours.from_now) }
+
+        it "refunds the held payment in full" do
+          described_class.new(request: req, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("refunded")
+          expect(payment.reload.fee_cents).to eq(0)
+        end
+      end
+
+      context "when cancelling less than 24 hours before scheduled time" do
+        before { req.update!(scheduled_at: 12.hours.from_now) }
+
+        it "charges a 50% cancellation fee" do
+          described_class.new(request: req, client: client, reason: "Changed my mind").call
+          payment.reload
+          expect(payment.status).to eq("refunded")
+          expect(payment.fee_cents).to eq(req.amount_cents / 2)
+        end
       end
     end
 
```
