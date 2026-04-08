# Experiment: 06-cancellation-fee
# App: request_clean | Model: opus | Run: 3
# Branch: experiment/06-cancellation-fee/request_clean/opus/run-3

---

## Claude Output

Done. Here's what I implemented:

**Migration** — Added `cancellation_fee_cents` column to `payments` (default 0).

**CancelService** (`app/services/requests/cancel_service.rb`) — Added `late_cancellation?` check: if `scheduled_at < 24.hours.from_now`, calls `PaymentGateway.partial_refund` with a 50% fee. Otherwise, full refund as before.

**PaymentGateway** (`app/services/payment_gateway.rb`) — Added `partial_refund` method that records the `cancellation_fee_cents` on the payment, marks it as refunded, and logs the split (refunded amount vs fee).

**Tests** — Updated cancel service spec with two payment scenarios: full refund for 24+ hours out, and 50% fee for < 24 hours.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/services/payment_gateway.rb b/affordance_request_clean/app/services/payment_gateway.rb
index be4203e..acc2b24 100644
--- a/affordance_request_clean/app/services/payment_gateway.rb
+++ b/affordance_request_clean/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, fee_cents:)
+    new(payment).partial_refund(fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,16 @@ def refund
     { success: true }
   end
 
+  def partial_refund(fee_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(cancellation_fee_cents: fee_cents)
+    @payment.refund!
+    refunded_amount = @payment.amount_cents - fee_cents
+    log("partial_refund", "payment_id=#{@payment.id} refunded=#{refunded_amount} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request_clean/app/services/requests/cancel_service.rb b/affordance_request_clean/app/services/requests/cancel_service.rb
index 546ae94..cc9c501 100644
--- a/affordance_request_clean/app/services/requests/cancel_service.rb
+++ b/affordance_request_clean/app/services/requests/cancel_service.rb
@@ -14,7 +14,12 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if late_cancellation?
+          fee_cents = @request.payment.amount_cents / 2
+          PaymentGateway.partial_refund(@request.payment, fee_cents: fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -25,6 +30,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request_clean/db/migrate/20260407222449_add_cancellation_fee_cents_to_payments.rb b/affordance_request_clean/db/migrate/20260407222449_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260407222449_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..6d2ca9b 100644
--- a/affordance_request_clean/db/schema.rb
+++ b/affordance_request_clean/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_222449) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -38,6 +38,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
@@ -78,7 +79,10 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
-    t.integer "provider_id", null: false
+    t.datetime "original_scheduled_at"
+    t.datetime "proposed_scheduled_at"
+    t.datetime "proposed_time"
+    t.integer "provider_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
diff --git a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
index a53df99..ab021f9 100644
--- a/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/cancel_service_spec.rb
@@ -24,9 +24,20 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment fully when canceled 24+ hours before" do
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(payment.cancellation_fee_cents).to eq(0)
+      end
+
+      context "when canceled less than 24 hours before scheduled time" do
+        let(:request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+
+        it "charges a 50% cancellation fee" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("refunded")
+          expect(payment.cancellation_fee_cents).to eq(payment.amount_cents / 2)
+        end
       end
     end
 
```
