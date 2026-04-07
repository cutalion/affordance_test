# Experiment: 06-cancellation-fee
# App: order | Model: opus | Run: 2
# Branch: experiment/06-cancellation-fee/order/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**Migration**: Added `cancellation_fee_cents` (integer, default 0) to the `orders` table.

**CancelService** (`app/services/orders/cancel_service.rb`):
- Added `late_cancellation?` check — true when `scheduled_at` is less than 24 hours away
- Late cancellations set `cancellation_fee_cents` to 50% of `amount_cents`
- If a held payment exists: updates payment amount to the fee and charges it (instead of refunding)
- If an already-charged payment exists: updates amount to the fee (keeps the charge)
- Non-late cancellations still get a full refund as before

**Tests**: 3 new test cases covering late cancellation with payment (charges 50%), late cancellation without payment (records fee), and verifying early cancellation still refunds fully.

---

## Git Diff

```diff
diff --git a/affordance_order/app/services/orders/cancel_service.rb b/affordance_order/app/services/orders/cancel_service.rb
index e04c1bc..6a91046 100644
--- a/affordance_order/app/services/orders/cancel_service.rb
+++ b/affordance_order/app/services/orders/cancel_service.rb
@@ -11,10 +11,20 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @order.cancel_reason = @reason
+
+      if late_cancellation?
+        @order.cancellation_fee_cents = (@order.amount_cents * 0.5).to_i
+      end
+
       @order.cancel!
 
       if @order.payment && %w[held charged].include?(@order.payment.status)
-        PaymentGateway.refund(@order.payment)
+        if @order.cancellation_fee_cents > 0
+          @order.payment.update!(amount_cents: @order.cancellation_fee_cents)
+          PaymentGateway.charge(@order.payment) if @order.payment.status == "held"
+        else
+          PaymentGateway.refund(@order.payment)
+        end
       end
 
       NotificationService.notify(@order.provider, :order_canceled, order_id: @order.id)
@@ -25,6 +35,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @order.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_order/db/migrate/20260407154554_add_cancellation_fee_cents_to_orders.rb b/affordance_order/db/migrate/20260407154554_add_cancellation_fee_cents_to_orders.rb
new file mode 100644
index 0000000..3a8ae3b
--- /dev/null
+++ b/affordance_order/db/migrate/20260407154554_add_cancellation_fee_cents_to_orders.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..92c755e 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_154554) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -38,7 +38,9 @@
 
   create_table "orders", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.string "bulk_id"
     t.text "cancel_reason"
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "client_id", null: false
     t.datetime "completed_at"
     t.datetime "created_at", null: false
@@ -46,12 +48,15 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
-    t.integer "provider_id", null: false
+    t.integer "proposed_duration_minutes"
+    t.datetime "proposed_scheduled_at"
+    t.integer "provider_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
     t.string "state", default: "pending", null: false
     t.datetime "updated_at", null: false
+    t.index ["bulk_id"], name: "index_orders_on_bulk_id"
     t.index ["client_id"], name: "index_orders_on_client_id"
     t.index ["provider_id"], name: "index_orders_on_provider_id"
     t.index ["scheduled_at"], name: "index_orders_on_scheduled_at"
@@ -60,6 +65,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
@@ -105,7 +111,7 @@
 
   add_foreign_key "cards", "clients"
   add_foreign_key "orders", "clients"
-  add_foreign_key "orders", "providers"
+  add_foreign_key "orders", "providers", on_delete: :nullify
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "orders"
   add_foreign_key "reviews", "orders"
diff --git a/affordance_order/spec/services/orders/cancel_service_spec.rb b/affordance_order/spec/services/orders/cancel_service_spec.rb
index b0ced7f..e979563 100644
--- a/affordance_order/spec/services/orders/cancel_service_spec.rb
+++ b/affordance_order/spec/services/orders/cancel_service_spec.rb
@@ -24,9 +24,31 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, order: order, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment when canceling 24+ hours before" do
         described_class.new(order: order, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(order.reload.cancellation_fee_cents).to eq(0)
+      end
+
+      context "when canceling less than 24 hours before scheduled time" do
+        let(:order) { create(:order, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+
+        it "charges 50% cancellation fee instead of refunding" do
+          described_class.new(order: order, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("charged")
+          expect(payment.amount_cents).to eq(175_000)
+          expect(order.reload.cancellation_fee_cents).to eq(175_000)
+        end
+      end
+    end
+
+    context "when canceling less than 24 hours before scheduled time without payment" do
+      let(:order) { create(:order, client: client, provider: provider, scheduled_at: 6.hours.from_now) }
+
+      it "records the cancellation fee on the order" do
+        result = described_class.new(order: order, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(order.reload.cancellation_fee_cents).to eq(175_000)
       end
     end
 
```
