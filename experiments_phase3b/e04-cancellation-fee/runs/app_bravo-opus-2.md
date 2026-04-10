# Experiment: e04-cancellation-fee
# App: app_bravo | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_bravo/opus/run-2

---

## Claude Output

Here's a summary of the changes:

**Migration** — `db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb`: Adds `cancellation_fee_cents` integer column (default 0) to the payments table.

**`Orders::CancelService`** — Two new private methods:
- `late_cancellation?` — returns true if `scheduled_at` is within 24 hours from now
- `cancellation_fee_cents` — calculates 50% of the order amount
- The `call` method now branches: late cancellations charge the fee via `PaymentGateway.charge_cancellation_fee`; early cancellations still get a full refund

**`PaymentGateway`** — New `charge_cancellation_fee(payment, fee_cents)` method that records the fee on the payment, charges the payment (status → "charged"), and logs the fee and refund amounts.

**API response** — `cancellation_fee_cents` is now included in the payment JSON within the order detail endpoint.

**Tests** — 3 new test cases:
- Cancellation within 24 hours charges 50% fee (held payment)
- Cancellation within 24 hours charges 50% fee (charged payment)
- Boundary case: exactly 24 hours is treated as late (fee applies)

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/orders_controller.rb b/app_bravo/app/controllers/api/orders_controller.rb
index 2418afc..692744c 100644
--- a/app_bravo/app/controllers/api/orders_controller.rb
+++ b/app_bravo/app/controllers/api/orders_controller.rb
@@ -149,6 +149,7 @@ def order_detail_json(order)
           id: order.payment.id,
           status: order.payment.status,
           amount_cents: order.payment.amount_cents,
+          cancellation_fee_cents: order.payment.cancellation_fee_cents,
           currency: order.payment.currency
         } : nil,
         created_at: order.created_at,
diff --git a/app_bravo/app/services/orders/cancel_service.rb b/app_bravo/app/services/orders/cancel_service.rb
index e04c1bc..8a62df9 100644
--- a/app_bravo/app/services/orders/cancel_service.rb
+++ b/app_bravo/app/services/orders/cancel_service.rb
@@ -14,7 +14,11 @@ def call
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+        if late_cancellation?
+          PaymentGateway.charge_cancellation_fee(@order.payment, cancellation_fee_cents)
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
@@ -25,6 +29,14 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at <= 24.hours.from_now
+    end
+
+    def cancellation_fee_cents
+      (@order.amount_cents * 0.5).to_i
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_bravo/app/services/payment_gateway.rb b/app_bravo/app/services/payment_gateway.rb
index 3530c85..95cd1f3 100644
--- a/app_bravo/app/services/payment_gateway.rb
+++ b/app_bravo/app/services/payment_gateway.rb
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
@@ -43,6 +47,16 @@ def refund
     { success: true }
   end
 
+  def charge_cancellation_fee(fee_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(cancellation_fee_cents: fee_cents)
+    @payment.charge!
+    refund_amount = @payment.amount_cents - fee_cents
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} refund=#{refund_amount}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_bravo/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb b/app_bravo/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/app_bravo/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..193a2d9 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -62,6 +62,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
diff --git a/app_bravo/spec/services/orders/cancel_service_spec.rb b/app_bravo/spec/services/orders/cancel_service_spec.rb
index b0ced7f..1f4eced 100644
--- a/app_bravo/spec/services/orders/cancel_service_spec.rb
+++ b/app_bravo/spec/services/orders/cancel_service_spec.rb
@@ -24,10 +24,45 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, order: order, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment when canceled more than 24 hours before scheduled time" do
         described_class.new(order: order, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
+
+      context "when canceled within 24 hours of scheduled time" do
+        let(:order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+
+        it "charges a 50% cancellation fee" do
+          described_class.new(order: order, client: client, reason: "Changed my mind").call
+          payment.reload
+          expect(payment.status).to eq("charged")
+          expect(payment.cancellation_fee_cents).to eq(order.amount_cents / 2)
+        end
+      end
+    end
+
+    context "when payment is charged and canceled within 24 hours" do
+      let(:order) { create(:order, client: client, provider: provider, scheduled_at: 6.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :charged, order: order, card: card) }
+
+      it "charges a 50% cancellation fee instead of refunding" do
+        described_class.new(order: order, client: client, reason: "Emergency").call
+        payment.reload
+        expect(payment.cancellation_fee_cents).to eq(order.amount_cents / 2)
+      end
+    end
+
+    context "when canceled at exactly 24 hours before scheduled time" do
+      let(:order) { create(:order, client: client, provider: provider, scheduled_at: 24.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, order: order, card: card) }
+
+      it "charges the cancellation fee (boundary is inclusive)" do
+        described_class.new(order: order, client: client, reason: "Changed my mind").call
+        payment.reload
+        expect(payment.cancellation_fee_cents).to eq(order.amount_cents / 2)
+      end
     end
 
     it "notifies the provider" do
```
