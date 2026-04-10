# Experiment: e04-cancellation-fee
# App: app_charlie | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_charlie/opus/run-2

---

## Claude Output

All 111 tests pass. Here's a summary of what I implemented:

**Migration**: Added `cancellation_fee_cents` column (integer, default 0) to the `payments` table.

**`PaymentGateway`** (`app/services/payment_gateway.rb`): Added `.partial_refund(payment, fee_cents:)` — records the cancellation fee on the payment, marks it as refunded, and logs the partial refund with the fee and refunded amounts.

**`Requests::CancelService`** (`app/services/requests/cancel_service.rb`): When a booking with a held/charged payment is canceled within 24 hours of `scheduled_at`, it now calls `partial_refund` with a 50% fee instead of a full refund. Cancellations more than 24 hours before the scheduled time still get a full refund.

**Tests**: Added specs for the cancellation fee scenario in `cancel_service_spec.rb` and for `partial_refund` in `payment_gateway_spec.rb`.

---

## Git Diff

```diff
diff --git a/app_charlie/app/services/payment_gateway.rb b/app_charlie/app/services/payment_gateway.rb
index be4203e..0a67b3f 100644
--- a/app_charlie/app/services/payment_gateway.rb
+++ b/app_charlie/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, fee_cents:)
+    new(payment).partial_refund(fee_cents: fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,16 @@ def refund
     { success: true }
   end
 
+  def partial_refund(fee_cents:)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(cancellation_fee_cents: fee_cents)
+    @payment.refund!
+    refund_amount = @payment.amount_cents - fee_cents
+    log("partial_refund", "payment_id=#{@payment.id} refunded=#{refund_amount} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_charlie/app/services/requests/cancel_service.rb b/app_charlie/app/services/requests/cancel_service.rb
index 546ae94..8461c2c 100644
--- a/app_charlie/app/services/requests/cancel_service.rb
+++ b/app_charlie/app/services/requests/cancel_service.rb
@@ -14,7 +14,12 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if within_24_hours_of_scheduled_time?
+          fee_cents = @request.payment.amount_cents / 2
+          PaymentGateway.partial_refund(@request.payment, fee_cents: fee_cents)
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
diff --git a/app_charlie/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb b/app_charlie/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb
new file mode 100644
index 0000000..a7827c8
--- /dev/null
+++ b/app_charlie/db/migrate/20260410120000_add_cancellation_fee_cents_to_payments.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..897c784 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140805) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
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
diff --git a/app_charlie/spec/services/payment_gateway_spec.rb b/app_charlie/spec/services/payment_gateway_spec.rb
index 8b2e52c..0444381 100644
--- a/app_charlie/spec/services/payment_gateway_spec.rb
+++ b/app_charlie/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,38 @@
       end
     end
   end
+
+  describe ".partial_refund" do
+    context "when payment is held" do
+      let(:card) { create(:card, :default, client: client) }
+      let(:payment) { create(:payment, :held, request: request, card: card, amount_cents: 350_000) }
+
+      it "returns success" do
+        result = PaymentGateway.partial_refund(payment, fee_cents: 175_000)
+        expect(result[:success]).to be true
+      end
+
+      it "sets the cancellation fee and refunds" do
+        PaymentGateway.partial_refund(payment, fee_cents: 175_000)
+        payment.reload
+        expect(payment.status).to eq("refunded")
+        expect(payment.cancellation_fee_cents).to eq(175_000)
+      end
+
+      it "writes to payment log with partial refund details" do
+        PaymentGateway.partial_refund(payment, fee_cents: 175_000)
+        expect(read_payment_log).to include("[PAYMENT] action=partial_refund")
+        expect(read_payment_log).to include("refunded=175000")
+        expect(read_payment_log).to include("fee=175000")
+      end
+    end
+
+    context "when payment is pending" do
+      it "returns failure" do
+        result = PaymentGateway.partial_refund(payment, fee_cents: 175_000)
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Payment not chargeable")
+      end
+    end
+  end
 end
diff --git a/app_charlie/spec/services/requests/cancel_service_spec.rb b/app_charlie/spec/services/requests/cancel_service_spec.rb
index 5458786..a99ce83 100644
--- a/app_charlie/spec/services/requests/cancel_service_spec.rb
+++ b/app_charlie/spec/services/requests/cancel_service_spec.rb
@@ -24,9 +24,21 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment fully when more than 24 hours before scheduled time" do
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
+        expect(payment.cancellation_fee_cents).to eq(0)
+      end
+
+      context "when within 24 hours of scheduled time" do
+        let(:request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+
+        it "charges a 50% cancellation fee" do
+          described_class.new(request: request, client: client, reason: "Changed my mind").call
+          payment.reload
+          expect(payment.status).to eq("refunded")
+          expect(payment.cancellation_fee_cents).to eq(payment.amount_cents / 2)
+        end
       end
     end
 
```
