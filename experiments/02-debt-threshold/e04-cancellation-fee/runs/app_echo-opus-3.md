# Experiment: e04-cancellation-fee
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e04-cancellation-fee/app_echo/opus/run-3

---

## Claude Output

All 138 tests pass. Here's a summary of the changes:

**Migration** — Added `cancellation_fee_cents` column to `payments` table (default 0).

**PaymentGateway** — Added `charge_cancellation_fee(fee_cents)` method that records the fee on the payment and moves it to refunded status, logging the fee and net refund amounts.

**CancelService** — When canceling a request with an active payment (held/charged), it now checks whether the cancellation is within 24 hours of `scheduled_at`. If so, it charges a 50% cancellation fee via the gateway instead of issuing a full refund. Cancellations more than 24 hours out still get a full refund.

---

## Git Diff

```diff
diff --git a/app_echo/app/services/payment_gateway.rb b/app_echo/app/services/payment_gateway.rb
index be4203e..38b60df 100644
--- a/app_echo/app/services/payment_gateway.rb
+++ b/app_echo/app/services/payment_gateway.rb
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
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def charge_cancellation_fee(fee_cents)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(cancellation_fee_cents: fee_cents)
+    @payment.refund!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} refunded=#{@payment.amount_cents - fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_echo/app/services/requests/cancel_service.rb b/app_echo/app/services/requests/cancel_service.rb
index 546ae94..c9e7180 100644
--- a/app_echo/app/services/requests/cancel_service.rb
+++ b/app_echo/app/services/requests/cancel_service.rb
@@ -14,7 +14,12 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if within_24_hours_of_scheduled_time?
+          fee_cents = @request.payment.amount_cents / 2
+          PaymentGateway.charge_cancellation_fee(@request.payment, fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -25,6 +30,10 @@ def call
 
     private
 
+    def within_24_hours_of_scheduled_time?
+      @request.scheduled_at - Time.current <= 24.hours
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_echo/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb b/app_echo/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/app_echo/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..f078330 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
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
diff --git a/app_echo/spec/services/requests/cancel_service_spec.rb b/app_echo/spec/services/requests/cancel_service_spec.rb
index 5458786..9f45d3b 100644
--- a/app_echo/spec/services/requests/cancel_service_spec.rb
+++ b/app_echo/spec/services/requests/cancel_service_spec.rb
@@ -24,9 +24,20 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment when more than 24 hours before scheduled time" do
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(payment.cancellation_fee_cents).to eq(0)
+      end
+
+      context "when canceled within 24 hours of scheduled time" do
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
