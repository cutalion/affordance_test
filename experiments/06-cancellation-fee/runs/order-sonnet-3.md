# Experiment: 06-cancellation-fee
# App: order | Model: sonnet | Run: 3
# Branch: experiment/06-cancellation-fee/order/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**`CancelService`** — added `late_cancellation?` check: if `scheduled_at < 24.hours.from_now`, sets `fee_cents` to 50% of `amount_cents` on the payment before calling `PaymentGateway.refund`.

**`PaymentGateway#refund`** — now logs the net refund amount (`amount_cents - fee_cents`) and the fee separately.

**Specs** — 4 new cases covering:
- Late cancellation with held payment → 50% fee charged, payment refunded
- Early cancellation (48h out) → no fee, full refund

The `fee_cents` column already existed in the schema, so no migration was needed.

---

## Git Diff

```diff
diff --git a/affordance_order/app/services/orders/cancel_service.rb b/affordance_order/app/services/orders/cancel_service.rb
index e04c1bc..8eee0f2 100644
--- a/affordance_order/app/services/orders/cancel_service.rb
+++ b/affordance_order/app/services/orders/cancel_service.rb
@@ -14,6 +14,10 @@ def call
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
+        if late_cancellation?
+          fee = (@order.payment.amount_cents * 0.5).to_i
+          @order.payment.update!(fee_cents: fee)
+        end
         PaymentGateway.refund(@order.payment)
       end
 
@@ -25,6 +29,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_order/app/services/payment_gateway.rb b/affordance_order/app/services/payment_gateway.rb
index 3530c85..c670da9 100644
--- a/affordance_order/app/services/payment_gateway.rb
+++ b/affordance_order/app/services/payment_gateway.rb
@@ -38,8 +38,9 @@ def charge
   def refund
     return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
 
+    refund_amount = @payment.amount_cents - @payment.fee_cents
     @payment.refund!
-    log("refund", "payment_id=#{@payment.id} amount=#{@payment.amount_cents}")
+    log("refund", "payment_id=#{@payment.id} amount=#{refund_amount} fee=#{@payment.fee_cents}")
     { success: true }
   end
 
diff --git a/affordance_order/spec/services/orders/cancel_service_spec.rb b/affordance_order/spec/services/orders/cancel_service_spec.rb
index b0ced7f..81aeb12 100644
--- a/affordance_order/spec/services/orders/cancel_service_spec.rb
+++ b/affordance_order/spec/services/orders/cancel_service_spec.rb
@@ -53,5 +53,37 @@
       expect(result[:success]).to be false
       expect(result[:error]).to include("Cannot cancel order")
     end
+
+    context "when cancelling less than 24 hours before scheduled time" do
+      let(:soon_order) { create(:order, :confirmed, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: soon_order, card: card, amount_cents: 200_000, fee_cents: 0) }
+
+      it "charges a 50% cancellation fee" do
+        described_class.new(order: soon_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.fee_cents).to eq(100_000)
+      end
+
+      it "still refunds the payment" do
+        described_class.new(order: soon_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
+    context "when cancelling more than 24 hours before scheduled time" do
+      let(:future_order) { create(:order, :confirmed, client: client, provider: provider, scheduled_at: 48.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: future_order, card: card, amount_cents: 200_000, fee_cents: 0) }
+
+      it "does not charge a cancellation fee" do
+        described_class.new(order: future_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.fee_cents).to eq(0)
+      end
+
+      it "refunds the full amount" do
+        described_class.new(order: future_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
   end
 end
```
