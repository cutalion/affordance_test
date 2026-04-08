# Experiment: 06-cancellation-fee
# App: request_clean | Model: opus | Run: 2
# Branch: experiment/06-cancellation-fee/request_clean/opus/run-2

---

## Claude Output

Done. Here's what I implemented:

**CancelService** (`app/services/requests/cancel_service.rb`): Added `late_cancellation?` check — if `scheduled_at` is less than 24 hours away, charges a 50% fee instead of refunding. Returns `cancellation_fee_cents` in the result hash.

**PaymentGateway** (`app/services/payment_gateway.rb`): Added `charge_cancellation_fee(payment, fee_cents)` — stores the fee on the payment record and marks the payment as charged.

**API response** (`app/controllers/api/requests_controller.rb`): Exposed `fee_cents` in the payment JSON.

**Tests**: Added two new specs — one for late cancellation (12h before, expects 50% fee charged) and one for early cancellation (3 days before, expects full refund with zero fee). All 267 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..cb80d44 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -149,6 +149,7 @@ def request_detail_json(request)
           id: request.payment.id,
           status: request.payment.status,
           amount_cents: request.payment.amount_cents,
+          fee_cents: request.payment.fee_cents,
           currency: request.payment.currency
         } : nil,
         created_at: request.created_at,
diff --git a/affordance_request_clean/app/services/payment_gateway.rb b/affordance_request_clean/app/services/payment_gateway.rb
index be4203e..9cf4bbe 100644
--- a/affordance_request_clean/app/services/payment_gateway.rb
+++ b/affordance_request_clean/app/services/payment_gateway.rb
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
+    @payment.update!(fee_cents: fee_cents)
+    @payment.charge!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} original_amount=#{@payment.amount_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request_clean/app/services/requests/cancel_service.rb b/affordance_request_clean/app/services/requests/cancel_service.rb
index 546ae94..14d036f 100644
--- a/affordance_request_clean/app/services/requests/cancel_service.rb
+++ b/affordance_request_clean/app/services/requests/cancel_service.rb
@@ -13,18 +13,29 @@ def call
       @request.cancel_reason = @reason
       @request.cancel!
 
+      cancellation_fee_cents = 0
+
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if late_cancellation?
+          cancellation_fee_cents = @request.payment.amount_cents / 2
+          PaymentGateway.charge_cancellation_fee(@request.payment, cancellation_fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
-      { success: true, request: @request }
+      { success: true, request: @request, cancellation_fee_cents: cancellation_fee_cents }
     rescue AASM::InvalidTransition
       error("Cannot cancel request in #{@request.state} state")
     end
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
index a53df99..0019916 100644
--- a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
@@ -30,6 +30,32 @@
       end
     end
 
+    context "when cancelling less than 24 hours before scheduled time" do
+      let(:soon_request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: soon_request, card: card, amount_cents: 350_000) }
+
+      it "charges a 50% cancellation fee" do
+        result = described_class.new(request: soon_request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(result[:cancellation_fee_cents]).to eq(175_000)
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.fee_cents).to eq(175_000)
+      end
+    end
+
+    context "when cancelling more than 24 hours before scheduled time" do
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: request, card: card) }
+
+      it "refunds fully with no cancellation fee" do
+        result = described_class.new(request: request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(result[:cancellation_fee_cents]).to eq(0)
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: request, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
