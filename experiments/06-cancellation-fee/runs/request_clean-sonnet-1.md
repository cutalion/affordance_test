# Experiment: 06-cancellation-fee
# App: request_clean | Model: sonnet | Run: 1
# Branch: experiment/06-cancellation-fee/request_clean/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**`Requests::CancelService`** — added `late_cancellation?` (checks `scheduled_at <= 24.hours.from_now`) and branches on it: charge a fee if late, refund if early.

**`Payment#cancellation_fee!(fee_cents:)`** — sets `fee_cents`, marks status as `"charged"` with `charged_at`.

**`PaymentGateway.charge_cancellation_fee(payment, fee_cents)`** — validates the payment is held/charged, calls `cancellation_fee!`, and logs the action.

**Specs** — existing refund test renamed to clarify it covers the >24h case; two new tests cover the <24h case (status becomes `"charged"`, `fee_cents` is 50% of amount).

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/models/payment.rb b/affordance_request_clean/app/models/payment.rb
index 305b83a..3d8ecdf 100644
--- a/affordance_request_clean/app/models/payment.rb
+++ b/affordance_request_clean/app/models/payment.rb
@@ -24,4 +24,8 @@ def charge!
   def refund!
     update!(status: "refunded", refunded_at: Time.current)
   end
+
+  def cancellation_fee!(fee_cents:)
+    update!(fee_cents: fee_cents, status: "charged", charged_at: Time.current)
+  end
 end
diff --git a/affordance_request_clean/app/services/payment_gateway.rb b/affordance_request_clean/app/services/payment_gateway.rb
index be4203e..9247b73 100644
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
@@ -43,6 +47,14 @@ def refund
     { success: true }
   end
 
+  def charge_cancellation_fee(fee_cents)
+    return { success: false, error: "No payment to charge fee on" } unless %w[held charged].include?(@payment.status)
+
+    @payment.cancellation_fee!(fee_cents: fee_cents)
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} card=*#{@payment.card.last_four}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request_clean/app/services/requests/cancel_service.rb b/affordance_request_clean/app/services/requests/cancel_service.rb
index 546ae94..1bf399d 100644
--- a/affordance_request_clean/app/services/requests/cancel_service.rb
+++ b/affordance_request_clean/app/services/requests/cancel_service.rb
@@ -14,7 +14,12 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if late_cancellation?
+          fee_cents = @request.amount_cents / 2
+          PaymentGateway.charge_cancellation_fee(@request.payment, fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -25,6 +30,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
index a53df99..332e281 100644
--- a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
@@ -20,16 +20,33 @@
       expect(confirmed_request.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when payment is held and cancellation is more than 24 hours before scheduled time" do
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment in full" do
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
     end
 
+    context "when payment is held and cancellation is less than 24 hours before scheduled time" do
+      let(:request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 350_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: request, card: card) }
+
+      it "charges 50% cancellation fee instead of refunding" do
+        described_class.new(request: request, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.reload.fee_cents).to eq(175_000)
+      end
+
+      it "does not refund the payment" do
+        described_class.new(request: request, client: client, reason: "Emergency").call
+        expect(payment.reload.status).not_to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: request, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
