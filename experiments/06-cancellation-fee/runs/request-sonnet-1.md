# Experiment: 06-cancellation-fee
# App: request | Model: sonnet | Run: 1
# Branch: experiment/06-cancellation-fee/request/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**Changes:**

- `db/migrate/..._add_cancellation_fee_cents_to_payments.rb` — adds `cancellation_fee_cents` column (integer, default 0) to payments
- `app/models/payment.rb` — adds `charge_cancellation_fee!(fee_cents)` method that sets status to `charged` and records the fee
- `app/services/payment_gateway.rb` — adds `charge_cancellation_fee(payment, fee_cents)` class/instance method with logging
- `app/services/requests/cancel_service.rb` — checks if `scheduled_at < 24.hours.from_now`; if so, charges a 50% fee instead of refunding
- `spec/services/requests/cancel_service_spec.rb` — two new tests covering the early vs late cancellation paths

---

## Git Diff

```diff
diff --git a/affordance_request/app/models/payment.rb b/affordance_request/app/models/payment.rb
index 305b83a..fecf826 100644
--- a/affordance_request/app/models/payment.rb
+++ b/affordance_request/app/models/payment.rb
@@ -24,4 +24,8 @@ def charge!
   def refund!
     update!(status: "refunded", refunded_at: Time.current)
   end
+
+  def charge_cancellation_fee!(fee_cents)
+    update!(status: "charged", charged_at: Time.current, cancellation_fee_cents: fee_cents)
+  end
 end
diff --git a/affordance_request/app/services/payment_gateway.rb b/affordance_request/app/services/payment_gateway.rb
index be4203e..e002ad8 100644
--- a/affordance_request/app/services/payment_gateway.rb
+++ b/affordance_request/app/services/payment_gateway.rb
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
+    return { success: false, error: "Payment not held" } unless @payment.status == "held"
+
+    @payment.charge_cancellation_fee!(fee_cents)
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} card=*#{@payment.card.last_four}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/affordance_request/app/services/requests/cancel_service.rb b/affordance_request/app/services/requests/cancel_service.rb
index 546ae94..e813801 100644
--- a/affordance_request/app/services/requests/cancel_service.rb
+++ b/affordance_request/app/services/requests/cancel_service.rb
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
+      @request.scheduled_at < 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/affordance_request/db/migrate/20260407130803_add_cancellation_fee_cents_to_payments.rb b/affordance_request/db/migrate/20260407130803_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..2eab4df
--- /dev/null
+++ b/affordance_request/db/migrate/20260407130803_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, null: false, default: 0
+  end
+end
diff --git a/affordance_request/db/schema.rb b/affordance_request/db/schema.rb
index 18c568a..93bc868 100644
--- a/affordance_request/db/schema.rb
+++ b/affordance_request/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_130803) do
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
@@ -78,7 +79,9 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
-    t.integer "provider_id", null: false
+    t.text "propose_reason"
+    t.datetime "proposed_scheduled_at"
+    t.integer "provider_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
diff --git a/affordance_request/spec/services/requests/cancel_service_spec.rb b/affordance_request/spec/services/requests/cancel_service_spec.rb
index 98e0d2f..ac3fd08 100644
--- a/affordance_request/spec/services/requests/cancel_service_spec.rb
+++ b/affordance_request/spec/services/requests/cancel_service_spec.rb
@@ -20,13 +20,27 @@
       expect(accepted_request.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when payment is held and canceling more than 24 hours before scheduled time" do
+      let(:req) { create(:request, :accepted, client: client, provider: provider, scheduled_at: 2.days.from_now) }
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: req, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment in full" do
         described_class.new(request: req, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(payment.reload.cancellation_fee_cents).to eq(0)
+      end
+    end
+
+    context "when payment is held and canceling less than 24 hours before scheduled time" do
+      let(:req) { create(:request, :accepted, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: req, card: card) }
+
+      it "charges a 50% cancellation fee instead of refunding" do
+        described_class.new(request: req, client: client, reason: "Last minute change").call
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.reload.cancellation_fee_cents).to eq(req.amount_cents / 2)
       end
     end
 
```
