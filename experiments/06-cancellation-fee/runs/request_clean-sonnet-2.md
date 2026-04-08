# Experiment: 06-cancellation-fee
# App: request_clean | Model: sonnet | Run: 2
# Branch: experiment/06-cancellation-fee/request_clean/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**`CancelService`** — extracted payment handling into `handle_payment_on_cancel`:
- If `scheduled_at < 24.hours.from_now` (late cancellation) and payment is held: charge the cancellation fee
- Otherwise: full refund as before

**`PaymentGateway`** — new `charge_cancellation_fee(fee_cents:)` method:
- Sets `fee_cents` to the provided amount (50% of `amount_cents`)
- Charges the held payment
- Logs the action

The `fee_cents` column was already present in the schema, so no migration was needed.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/services/payment_gateway.rb b/affordance_request_clean/app/services/payment_gateway.rb
index be4203e..0132a7b 100644
--- a/affordance_request_clean/app/services/payment_gateway.rb
+++ b/affordance_request_clean/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.charge_cancellation_fee(payment, fee_cents:)
+    new(payment).charge_cancellation_fee(fee_cents: fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def charge_cancellation_fee(fee_cents:)
+    return { success: false, error: "Payment not held" } unless @payment.status == "held"
+
+    @payment.update!(fee_cents: fee_cents)
+    @payment.charge!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} card=*#{@payment.card.last_four}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request_clean/app/services/requests/cancel_service.rb b/affordance_request_clean/app/services/requests/cancel_service.rb
index 546ae94..17b4a26 100644
--- a/affordance_request_clean/app/services/requests/cancel_service.rb
+++ b/affordance_request_clean/app/services/requests/cancel_service.rb
@@ -13,9 +13,7 @@ def call
       @request.cancel_reason = @reason
       @request.cancel!
 
-      if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
-      end
+      handle_payment_on_cancel
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
       { success: true, request: @request }
@@ -25,6 +23,22 @@ def call
 
     private
 
+    def handle_payment_on_cancel
+      payment = @request.payment
+      return unless payment && %w[held charged].include?(payment.status)
+
+      if late_cancellation?
+        fee_cents = @request.amount_cents / 2
+        PaymentGateway.charge_cancellation_fee(payment, fee_cents: fee_cents)
+      else
+        PaymentGateway.refund(payment)
+      end
+    end
+
+    def late_cancellation?
+      @request.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
index a53df99..1db6b76 100644
--- a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
@@ -20,7 +20,7 @@
       expect(confirmed_request.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when payment is held and cancellation is >= 24 hours before scheduled time" do
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
@@ -30,6 +30,22 @@
       end
     end
 
+    context "when payment is held and cancellation is < 24 hours before scheduled time" do
+      let(:soon_request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 350_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: soon_request, card: card, amount_cents: 350_000) }
+
+      it "charges the cancellation fee instead of refunding" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("charged")
+      end
+
+      it "sets fee_cents to 50% of the amount" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(payment.reload.fee_cents).to eq(175_000)
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: request, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
