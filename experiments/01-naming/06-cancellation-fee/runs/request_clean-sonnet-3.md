# Experiment: 06-cancellation-fee
# App: request_clean | Model: sonnet | Run: 3
# Branch: experiment/06-cancellation-fee/request_clean/sonnet/run-3

---

## Claude Output

Done. Changes made in `Requests::CancelService`:

- **`late_cancellation?`** — returns true if `scheduled_at - Time.current < 24 hours`
- **`handle_payment_on_cancel`** — routes to fee charging or full refund based on timing
- **`charge_cancellation_fee`** — updates payment amount to 50%, holds if pending, then charges

Tests cover late cancellation with held payment, late cancellation with pending payment, and on-time cancellation still getting a full refund. All 10 specs pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/services/requests/cancel_service.rb b/affordance_request_clean/app/services/requests/cancel_service.rb
index 546ae94..df96b89 100644
--- a/affordance_request_clean/app/services/requests/cancel_service.rb
+++ b/affordance_request_clean/app/services/requests/cancel_service.rb
@@ -1,5 +1,8 @@
 module Requests
   class CancelService
+    LATE_CANCELLATION_WINDOW = 24.hours
+    CANCELLATION_FEE_RATIO = 0.5
+
     def initialize(request:, client:, reason:)
       @request = request
       @client = client
@@ -13,9 +16,7 @@ def call
       @request.cancel_reason = @reason
       @request.cancel!
 
-      if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
-      end
+      handle_payment_on_cancel
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
       { success: true, request: @request }
@@ -25,6 +26,28 @@ def call
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at - Time.current < LATE_CANCELLATION_WINDOW
+    end
+
+    def handle_payment_on_cancel
+      return unless @request.payment
+
+      if late_cancellation?
+        charge_cancellation_fee(@request.payment)
+      elsif %w[held charged].include?(@request.payment.status)
+        PaymentGateway.refund(@request.payment)
+      end
+    end
+
+    def charge_cancellation_fee(payment)
+      fee_cents = (@request.amount_cents * CANCELLATION_FEE_RATIO).to_i
+      payment.update!(amount_cents: fee_cents)
+
+      PaymentGateway.hold(payment) if payment.status == "pending"
+      PaymentGateway.charge(payment) if payment.status == "held"
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
index a53df99..12c9244 100644
--- a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
@@ -30,6 +30,43 @@
       end
     end
 
+    context "when canceling within 24 hours of the scheduled time" do
+      let(:request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 100_000) }
+
+      context "when payment is held" do
+        let!(:card) { create(:card, :default, client: client) }
+        let!(:payment) { create(:payment, :held, request: request, amount_cents: 100_000, card: card) }
+
+        it "charges 50% as a cancellation fee instead of refunding" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("charged")
+          expect(payment.reload.amount_cents).to eq(50_000)
+        end
+      end
+
+      context "when payment is pending" do
+        let!(:card) { create(:card, :default, client: client) }
+        let!(:payment) { create(:payment, request: request, amount_cents: 100_000) }
+
+        it "holds and charges 50% as a cancellation fee" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("charged")
+          expect(payment.reload.amount_cents).to eq(50_000)
+        end
+      end
+    end
+
+    context "when canceling more than 24 hours before the scheduled time" do
+      let(:request) { create(:request, client: client, provider: provider, scheduled_at: 48.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: request, card: card) }
+
+      it "refunds the full payment" do
+        described_class.new(request: request, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: request, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
