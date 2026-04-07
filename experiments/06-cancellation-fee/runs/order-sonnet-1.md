# Experiment: 06-cancellation-fee
# App: order | Model: sonnet | Run: 1
# Branch: experiment/06-cancellation-fee/order/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**`app/services/orders/cancel_service.rb`** — added `late_cancellation?` check. If cancellation is < 24h before `scheduled_at`:
- Sets `payment.fee_cents = order.amount_cents / 2` (50% fee)
- Calls `PaymentGateway.charge` (captures the held payment) instead of refunding

**`spec/services/orders/cancel_service_spec.rb`** — added 3 new tests:
- Late cancellation charges 50% fee into `fee_cents`
- Late cancellation charges the payment (not refunds)
- Early cancellation still refunds with no fee

The `payments` table already had the `fee_cents` column (default 0), so no migration was needed. All 268 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/services/orders/cancel_service.rb b/affordance_order/app/services/orders/cancel_service.rb
index e04c1bc..7f8fd02 100644
--- a/affordance_order/app/services/orders/cancel_service.rb
+++ b/affordance_order/app/services/orders/cancel_service.rb
@@ -14,7 +14,13 @@ def call
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+        if late_cancellation?
+          fee_cents = @order.amount_cents / 2
+          @order.payment.update!(fee_cents: fee_cents)
+          PaymentGateway.charge(@order.payment)
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
@@ -25,6 +31,10 @@ def call
 
     private
 
+    def late_cancellation?
+      Time.current > @order.scheduled_at - 24.hours
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_order/spec/services/orders/cancel_service_spec.rb b/affordance_order/spec/services/orders/cancel_service_spec.rb
index b0ced7f..2e40373 100644
--- a/affordance_order/spec/services/orders/cancel_service_spec.rb
+++ b/affordance_order/spec/services/orders/cancel_service_spec.rb
@@ -53,5 +53,33 @@
       expect(result[:success]).to be false
       expect(result[:error]).to include("Cannot cancel order")
     end
+
+    context "when cancelled less than 24 hours before scheduled time" do
+      let(:late_order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 10_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: late_order, card: card, amount_cents: 10_000, fee_cents: 0) }
+
+      it "charges a 50% cancellation fee" do
+        described_class.new(order: late_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.fee_cents).to eq(5_000)
+      end
+
+      it "charges the payment instead of refunding" do
+        described_class.new(order: late_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("charged")
+      end
+    end
+
+    context "when cancelled more than 24 hours before scheduled time" do
+      let(:early_order) { create(:order, client: client, provider: provider, scheduled_at: 25.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: early_order, card: card, amount_cents: 10_000, fee_cents: 0) }
+
+      it "refunds the payment without a cancellation fee" do
+        described_class.new(order: early_order, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("refunded")
+        expect(payment.reload.fee_cents).to eq(0)
+      end
+    end
   end
 end
```
