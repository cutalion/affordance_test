# Experiment: e04-cancellation-fee
# App: app_echo | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_echo/opus/run-2

---

## Claude Output

All passing. Here's a summary of the changes:

**Migration**: Added `cancellation_fee_cents` (integer, default 0) to the `payments` table.

**`CancelService`**: When canceling, checks if `scheduled_at` is within 24 hours. If so, calculates a 50% cancellation fee (`amount_cents * 50 / 100`) and passes it to the payment gateway during refund.

**`PaymentGateway#refund`**: Now accepts an optional `cancellation_fee_cents:` keyword argument. When non-zero, it records the fee on the payment record before processing the refund.

The refund still transitions the payment to "refunded" status — the `cancellation_fee_cents` field tracks how much of the original amount the client forfeits. The actual refund amount would be `amount_cents - cancellation_fee_cents`.

---

## Git Diff

```diff
diff --git a/app_echo/app/services/payment_gateway.rb b/app_echo/app/services/payment_gateway.rb
index be4203e..5bb0546 100644
--- a/app_echo/app/services/payment_gateway.rb
+++ b/app_echo/app/services/payment_gateway.rb
@@ -9,8 +9,8 @@ def self.charge(payment)
     new(payment).charge
   end
 
-  def self.refund(payment)
-    new(payment).refund
+  def self.refund(payment, cancellation_fee_cents: 0)
+    new(payment).refund(cancellation_fee_cents: cancellation_fee_cents)
   end
 
   def initialize(payment)
@@ -35,11 +35,12 @@ def charge
     { success: true }
   end
 
-  def refund
+  def refund(cancellation_fee_cents: 0)
     return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
 
+    @payment.update!(cancellation_fee_cents: cancellation_fee_cents) if cancellation_fee_cents > 0
     @payment.refund!
-    log("refund", "payment_id=#{@payment.id} amount=#{@payment.amount_cents}")
+    log("refund", "payment_id=#{@payment.id} amount=#{@payment.amount_cents} cancellation_fee=#{cancellation_fee_cents}")
     { success: true }
   end
 
diff --git a/app_echo/app/services/requests/cancel_service.rb b/app_echo/app/services/requests/cancel_service.rb
index 546ae94..d238d29 100644
--- a/app_echo/app/services/requests/cancel_service.rb
+++ b/app_echo/app/services/requests/cancel_service.rb
@@ -6,6 +6,8 @@ def initialize(request:, client:, reason:)
       @reason = reason
     end
 
+    CANCELLATION_FEE_PERCENTAGE = 50
+
     def call
       return error("Not your request") unless @request.client_id == @client.id
       return error("Cancel reason is required") if @reason.blank?
@@ -14,7 +16,8 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        fee_cents = late_cancellation? ? (@request.amount_cents * CANCELLATION_FEE_PERCENTAGE / 100) : 0
+        PaymentGateway.refund(@request.payment, cancellation_fee_cents: fee_cents)
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -25,6 +28,10 @@ def call
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at <= 24.hours.from_now
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_echo/db/migrate/20260409191158_add_cancellation_fee_cents_to_payments.rb b/app_echo/db/migrate/20260409191158_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/app_echo/db/migrate/20260409191158_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index c2c99cb..5f92434 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_084335) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_191158) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -56,6 +56,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
@@ -91,8 +92,10 @@
     t.integer "amount_cents", null: false
     t.integer "announcement_id"
     t.text "cancel_reason"
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.text "counter_proposal_message"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.text "decline_reason"
@@ -101,6 +104,7 @@
     t.string "location"
     t.text "notes"
     t.integer "proposed_amount_cents"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.string "recurring_group_id"
     t.integer "recurring_index"
diff --git a/app_echo/spec/services/requests/cancel_service_spec.rb b/app_echo/spec/services/requests/cancel_service_spec.rb
index 5458786..ab877ad 100644
--- a/app_echo/spec/services/requests/cancel_service_spec.rb
+++ b/app_echo/spec/services/requests/cancel_service_spec.rb
@@ -28,6 +28,29 @@
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
+
+      context "when canceled within 24 hours of scheduled time" do
+        let(:request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+
+        it "charges a 50% cancellation fee" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          expect(payment.reload.cancellation_fee_cents).to eq(request.amount_cents / 2)
+        end
+
+        it "still refunds the payment" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          expect(payment.reload.status).to eq("refunded")
+        end
+      end
+
+      context "when canceled more than 24 hours before scheduled time" do
+        let(:request) { create(:request, client: client, provider: provider, scheduled_at: 3.days.from_now) }
+
+        it "does not charge a cancellation fee" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          expect(payment.reload.cancellation_fee_cents).to eq(0)
+        end
+      end
     end
 
     it "notifies the provider" do
```
