# Experiment: e04-cancellation-fee
# App: app_echo | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_echo/opus/run-1

---

## Claude Output

All 146 tests pass. Here's a summary of the changes:

**Migration** — Added `cancellation_fee_cents` (integer, default 0) to the `payments` table.

**`Request#late_cancellation?`** — Returns `true` when `scheduled_at` is within 24 hours of now.

**`PaymentGateway.charge_cancellation_fee(payment, fee_cents)`** — Sets `cancellation_fee_cents` on the payment and charges it (transitions status to `charged`), logging the action.

**`Requests::CancelService`** — Updated the payment handling: if the cancellation is late (within 24 hours of scheduled time), it charges a 50% cancellation fee instead of issuing a full refund. Cancellations made more than 24 hours before the scheduled time still get a full refund.

---

## Git Diff

```diff
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..6ec363b 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -29,6 +29,10 @@ class Request < ApplicationRecord
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
 
+  def late_cancellation?
+    scheduled_at <= 24.hours.from_now
+  end
+
   aasm column: :state do
     state :pending, initial: true
     state :accepted
diff --git a/app_echo/app/services/payment_gateway.rb b/app_echo/app/services/payment_gateway.rb
index be4203e..478a4a6 100644
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
+    @payment.charge!
+    log("cancellation_fee", "payment_id=#{@payment.id} fee=#{fee_cents} original_amount=#{@payment.amount_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_echo/app/services/requests/cancel_service.rb b/app_echo/app/services/requests/cancel_service.rb
index 546ae94..328467a 100644
--- a/app_echo/app/services/requests/cancel_service.rb
+++ b/app_echo/app/services/requests/cancel_service.rb
@@ -14,7 +14,12 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if @request.late_cancellation?
+          fee_cents = @request.amount_cents / 2
+          PaymentGateway.charge_cancellation_fee(@request.payment, fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
diff --git a/app_echo/db/migrate/20260410080327_add_cancellation_fee_cents_to_payments.rb b/app_echo/db/migrate/20260410080327_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/app_echo/db/migrate/20260410080327_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..7cc62e0 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_080327) do
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
diff --git a/app_echo/spec/models/request_spec.rb b/app_echo/spec/models/request_spec.rb
index a9aece5..b1a7847 100644
--- a/app_echo/spec/models/request_spec.rb
+++ b/app_echo/spec/models/request_spec.rb
@@ -182,6 +182,23 @@
     end
   end
 
+  describe "#late_cancellation?" do
+    it "returns true when scheduled within 24 hours" do
+      request = build(:request, scheduled_at: 12.hours.from_now)
+      expect(request.late_cancellation?).to be true
+    end
+
+    it "returns true when scheduled exactly 24 hours from now" do
+      request = build(:request, scheduled_at: 24.hours.from_now)
+      expect(request.late_cancellation?).to be true
+    end
+
+    it "returns false when scheduled more than 24 hours away" do
+      request = build(:request, scheduled_at: 25.hours.from_now)
+      expect(request.late_cancellation?).to be false
+    end
+  end
+
   describe "scopes" do
     let!(:future_request) { create(:request, scheduled_at: 1.day.from_now) }
     let!(:past_request) { create(:request, scheduled_at: 1.day.ago) }
diff --git a/app_echo/spec/services/payment_gateway_spec.rb b/app_echo/spec/services/payment_gateway_spec.rb
index 8b2e52c..dbdf516 100644
--- a/app_echo/spec/services/payment_gateway_spec.rb
+++ b/app_echo/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,40 @@
       end
     end
   end
+
+  describe ".charge_cancellation_fee" do
+    context "when payment is held" do
+      let(:card) { create(:card, :default, client: client) }
+      let(:payment) { create(:payment, :held, request: request, card: card) }
+
+      it "returns success" do
+        result = PaymentGateway.charge_cancellation_fee(payment, 175_000)
+        expect(result[:success]).to be true
+      end
+
+      it "sets cancellation_fee_cents on the payment" do
+        PaymentGateway.charge_cancellation_fee(payment, 175_000)
+        expect(payment.reload.cancellation_fee_cents).to eq(175_000)
+      end
+
+      it "charges the payment" do
+        PaymentGateway.charge_cancellation_fee(payment, 175_000)
+        expect(payment.reload.status).to eq("charged")
+      end
+
+      it "writes to payment log" do
+        PaymentGateway.charge_cancellation_fee(payment, 175_000)
+        expect(read_payment_log).to include("[PAYMENT] action=cancellation_fee")
+        expect(read_payment_log).to include("fee=175000")
+      end
+    end
+
+    context "when payment is pending" do
+      it "returns failure" do
+        result = PaymentGateway.charge_cancellation_fee(payment, 175_000)
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Payment not chargeable")
+      end
+    end
+  end
 end
diff --git a/app_echo/spec/services/requests/cancel_service_spec.rb b/app_echo/spec/services/requests/cancel_service_spec.rb
index 5458786..1752197 100644
--- a/app_echo/spec/services/requests/cancel_service_spec.rb
+++ b/app_echo/spec/services/requests/cancel_service_spec.rb
@@ -24,10 +24,21 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment when canceled more than 24 hours before scheduled time" do
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
+
+      context "when canceled within 24 hours of scheduled time" do
+        let(:request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+
+        it "charges a 50% cancellation fee instead of refunding" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          payment.reload
+          expect(payment.status).to eq("charged")
+          expect(payment.cancellation_fee_cents).to eq(request.amount_cents / 2)
+        end
+      end
     end
 
     it "notifies the provider" do
```
