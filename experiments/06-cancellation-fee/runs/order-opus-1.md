# Experiment: 06-cancellation-fee
# App: order | Model: opus | Run: 1
# Branch: experiment/06-cancellation-fee/order/opus/run-1

---

## Claude Output

Done. Here's what I implemented:

**Cancel service** (`app/services/orders/cancel_service.rb`):
- Added `late_cancellation?` check — returns true when `scheduled_at < 24.hours.from_now`
- When late and a payment exists (held/charged): sets `payment.fee_cents` to 50% of `order.amount_cents` before refunding
- Returns `cancellation_fee_cents` in the result hash (0 for non-late cancellations)

**Tests** (`spec/services/orders/cancel_service_spec.rb`):
- Added test for late cancellation (12h before) — verifies 50% fee is charged and recorded
- Added test for normal cancellation (3 days out) — verifies no fee and full refund

---

## Git Diff

```diff
diff --git a/affordance_order/app/services/orders/cancel_service.rb b/affordance_order/app/services/orders/cancel_service.rb
index e04c1bc..93e55c9 100644
--- a/affordance_order/app/services/orders/cancel_service.rb
+++ b/affordance_order/app/services/orders/cancel_service.rb
@@ -13,18 +13,27 @@ def call
       @order.cancel_reason = @reason
       @order.cancel!
 
+      fee_cents = 0
       if @order.payment && %w[held charged].include?(@order.payment.status)
+        if late_cancellation?
+          fee_cents = @order.amount_cents / 2
+          @order.payment.update!(fee_cents: fee_cents)
+        end
         PaymentGateway.refund(@order.payment)
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
-      { success: true, order: @order }
+      { success: true, order: @order, cancellation_fee_cents: fee_cents }
     rescue AASM::InvalidTransition
       error("Cannot cancel order in #{@order.state} state")
     end
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_order/spec/services/orders/cancel_service_spec.rb b/affordance_order/spec/services/orders/cancel_service_spec.rb
index b0ced7f..39c4aeb 100644
--- a/affordance_order/spec/services/orders/cancel_service_spec.rb
+++ b/affordance_order/spec/services/orders/cancel_service_spec.rb
@@ -30,6 +30,33 @@
       end
     end
 
+    context "when cancelling less than 24 hours before scheduled time" do
+      let(:soon_order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: soon_order, card: card, amount_cents: soon_order.amount_cents) }
+
+      it "charges a 50% cancellation fee" do
+        result = described_class.new(order: soon_order, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(result[:cancellation_fee_cents]).to eq(soon_order.amount_cents / 2)
+        expect(payment.reload.fee_cents).to eq(soon_order.amount_cents / 2)
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
+    context "when cancelling more than 24 hours before scheduled time" do
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: order, card: card, amount_cents: order.amount_cents, fee_cents: 0) }
+
+      it "does not charge a cancellation fee" do
+        result = described_class.new(order: order, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(result[:cancellation_fee_cents]).to eq(0)
+        expect(payment.reload.fee_cents).to eq(0)
+        expect(payment.reload.status).to eq("refunded")
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(order: order, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=order_canceled")
```
