# Experiment: 06-cancellation-fee
# App: request | Model: opus | Run: 2
# Branch: experiment/06-cancellation-fee/request/opus/run-2

---

## Claude Output

Done. Here's what I implemented:

**`app/services/requests/cancel_service.rb`** — Added a `late_cancellation?` check: if `scheduled_at` is less than 24 hours away, a 50% fee (`amount_cents / 2`) is recorded on the payment's `fee_cents` column before the refund is processed.

**Tests added** — Two new contexts covering:
- Late cancellation (< 24h): verifies 50% fee is charged and payment is still refunded
- Early cancellation (> 24h): verifies no fee is charged and full refund occurs

---

## Git Diff

```diff
diff --git a/affordance_request/app/services/requests/cancel_service.rb b/affordance_request/app/services/requests/cancel_service.rb
index 546ae94..458c93b 100644
--- a/affordance_request/app/services/requests/cancel_service.rb
+++ b/affordance_request/app/services/requests/cancel_service.rb
@@ -14,6 +14,10 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
+        if late_cancellation?
+          fee_cents = @request.payment.amount_cents / 2
+          @request.payment.update!(fee_cents: fee_cents)
+        end
         PaymentGateway.refund(@request.payment)
       end
 
@@ -25,6 +29,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request/spec/services/requests/cancel_service_spec.rb b/affordance_request/spec/services/requests/cancel_service_spec.rb
index 98e0d2f..1d4dfd1 100644
--- a/affordance_request/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request/spec/services/requests/cancel_service_spec.rb
@@ -28,6 +28,36 @@
         described_class.new(request: req, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
+
+      context "when canceling less than 24 hours before scheduled time" do
+        let(:req) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+        let!(:payment) { create(:payment, :held, request: req, card: card, amount_cents: 10_000, fee_cents: 0) }
+
+        it "charges a 50% cancellation fee" do
+          described_class.new(request: req, client: client, reason: "Changed my mind").call
+          expect(payment.reload.fee_cents).to eq(5_000)
+        end
+
+        it "still refunds the payment" do
+          described_class.new(request: req, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("refunded")
+        end
+      end
+
+      context "when canceling more than 24 hours before scheduled time" do
+        let(:req) { create(:request, client: client, provider: provider, scheduled_at: 48.hours.from_now) }
+        let!(:payment) { create(:payment, :held, request: req, card: card, amount_cents: 10_000, fee_cents: 0) }
+
+        it "does not charge a cancellation fee" do
+          described_class.new(request: req, client: client, reason: "Changed my mind").call
+          expect(payment.reload.fee_cents).to eq(0)
+        end
+
+        it "refunds the payment in full" do
+          described_class.new(request: req, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("refunded")
+        end
+      end
     end
 
     it "notifies the provider" do
```
