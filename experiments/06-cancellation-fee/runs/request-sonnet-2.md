# Experiment: 06-cancellation-fee
# App: request | Model: sonnet | Run: 2
# Branch: experiment/06-cancellation-fee/request/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**`CancelService`** — added `late_cancellation?` which checks if `scheduled_at - Time.current < 24.hours`. On cancel, if payment is held/charged:
- Late cancellation → `PaymentGateway.charge_cancellation_fee`
- Early cancellation → `PaymentGateway.refund` (existing behavior)

**`PaymentGateway`** — added `charge_cancellation_fee` which halves `amount_cents` and charges the payment.

**Specs** — split the "payment held" context into early vs late cancellation scenarios, 9 specs all passing.

---

## Git Diff

```diff
diff --git a/affordance_request/app/services/payment_gateway.rb b/affordance_request/app/services/payment_gateway.rb
index be4203e..d257351 100644
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
+    fee = (@payment.amount_cents / 2.0).ceil
+    @payment.update!(amount_cents: fee)
+    @payment.charge!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee} card=*#{@payment.card.last_four}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request/app/services/requests/cancel_service.rb b/affordance_request/app/services/requests/cancel_service.rb
index 546ae94..4c5d14e 100644
--- a/affordance_request/app/services/requests/cancel_service.rb
+++ b/affordance_request/app/services/requests/cancel_service.rb
@@ -14,7 +14,11 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if late_cancellation?
+          PaymentGateway.charge_cancellation_fee(@request.payment)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -28,5 +32,9 @@ def call
     def error(message)
       { success: false, error: message }
     end
+
+    def late_cancellation?
+      @request.scheduled_at - Time.current < 24.hours
+    end
   end
 end
diff --git a/affordance_request/spec/factories/requests.rb b/affordance_request/spec/factories/requests.rb
index ba19812..699d04d 100644
--- a/affordance_request/spec/factories/requests.rb
+++ b/affordance_request/spec/factories/requests.rb
@@ -61,5 +61,9 @@
     trait :scheduled_tomorrow do
       scheduled_at { 1.day.from_now }
     end
+
+    trait :scheduled_soon do
+      scheduled_at { 12.hours.from_now }
+    end
   end
 end
diff --git a/affordance_request/spec/services/requests/cancel_service_spec.rb b/affordance_request/spec/services/requests/cancel_service_spec.rb
index 98e0d2f..6fea178 100644
--- a/affordance_request/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request/spec/services/requests/cancel_service_spec.rb
@@ -20,7 +20,7 @@
       expect(accepted_request.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when payment is held and cancellation is more than 24 hours before scheduled time" do
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: req, card: card) }
 
@@ -30,6 +30,23 @@
       end
     end
 
+    context "when payment is held and cancellation is less than 24 hours before scheduled time" do
+      let(:req) { create(:request, :scheduled_soon, client: client, provider: provider) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: req, card: card, amount_cents: 100_000) }
+
+      it "charges 50% cancellation fee instead of refunding" do
+        described_class.new(request: req, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.reload.amount_cents).to eq(50_000)
+      end
+
+      it "does not refund the payment" do
+        described_class.new(request: req, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).not_to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: req, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
