# Experiment: e04-cancellation-fee
# App: app_charlie | Model: opus | Run: 3
# Branch: debt_experiment/e04-cancellation-fee/app_charlie/opus/run-3

---

## Claude Output

All 111 tests pass, including 5 new tests for the cancellation fee. Here's a summary of the changes:

**Migration** — `db/migrate/20260410075344_add_cancellation_fee_to_payments.rb`
- Added `cancellation_fee_cents` (integer, default 0) and `refund_amount_cents` (integer) to `payments`

**CancelService** — `app/services/requests/cancel_service.rb`
- Added `late_cancellation?` check: fee applies when `scheduled_at - now < 24 hours`
- Late cancellation: charges 50% of booking amount as fee, partial refund for the rest
- Early cancellation: full refund (unchanged behavior)

**PaymentGateway** — `app/services/payment_gateway.rb`
- Added `partial_refund` class/instance method that records `cancellation_fee_cents` and `refund_amount_cents` on the payment, marks it refunded, and logs the partial refund

**Tests** — `spec/services/requests/cancel_service_spec.rb`
- Within 24h: verifies 50% fee is charged and 50% is refunded
- Beyond 24h: verifies no fee and full refund
- Boundary (exactly 24h): verifies no fee (uses `freeze_time` for precision)

---

## Git Diff

```diff
diff --git a/app_charlie/app/services/payment_gateway.rb b/app_charlie/app/services/payment_gateway.rb
index be4203e..abca3a2 100644
--- a/app_charlie/app/services/payment_gateway.rb
+++ b/app_charlie/app/services/payment_gateway.rb
@@ -13,6 +13,10 @@ def self.refund(payment)
     new(payment).refund
   end
 
+  def self.partial_refund(payment, refund_amount_cents:, cancellation_fee_cents:)
+    new(payment).partial_refund(refund_amount_cents: refund_amount_cents, cancellation_fee_cents: cancellation_fee_cents)
+  end
+
   def initialize(payment)
     @payment = payment
   end
@@ -43,6 +47,15 @@ def refund
     { success: true }
   end
 
+  def partial_refund(refund_amount_cents:, cancellation_fee_cents:)
+    return { success: false, error: "Payment not chargeable" } unless %w[held charged].include?(@payment.status)
+
+    @payment.update!(cancellation_fee_cents: cancellation_fee_cents, refund_amount_cents: refund_amount_cents)
+    @payment.refund!
+    log("partial_refund", "payment_id=#{@payment.id} refund=#{refund_amount_cents} fee=#{cancellation_fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_charlie/app/services/requests/cancel_service.rb b/app_charlie/app/services/requests/cancel_service.rb
index 546ae94..86b67ad 100644
--- a/app_charlie/app/services/requests/cancel_service.rb
+++ b/app_charlie/app/services/requests/cancel_service.rb
@@ -14,7 +14,13 @@ def call
       @request.cancel!
 
       if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+        if late_cancellation?
+          fee_cents = @request.amount_cents / 2
+          refund_cents = @request.payment.amount_cents - fee_cents
+          PaymentGateway.partial_refund(@request.payment, refund_amount_cents: refund_cents, cancellation_fee_cents: fee_cents)
+        else
+          PaymentGateway.refund(@request.payment)
+        end
       end
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
@@ -25,6 +31,10 @@ def call
 
     private
 
+    def late_cancellation?
+      (@request.scheduled_at - Time.current) < 24.hours
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_charlie/db/migrate/20260410075344_add_cancellation_fee_to_payments.rb b/app_charlie/db/migrate/20260410075344_add_cancellation_fee_to_payments.rb
new file mode 100644
index 0000000..e6d67a6
--- /dev/null
+++ b/app_charlie/db/migrate/20260410075344_add_cancellation_fee_to_payments.rb
@@ -0,0 +1,6 @@
+class AddCancellationFeeToPayments < ActiveRecord::Migration[8.1]
+  def change
+    add_column :payments, :cancellation_fee_cents, :integer, default: 0, null: false
+    add_column :payments, :refund_amount_cents, :integer
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..0402df8 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140805) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_075344) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -38,12 +38,14 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.integer "fee_cents", default: 0, null: false
     t.datetime "held_at"
+    t.integer "refund_amount_cents"
     t.datetime "refunded_at"
     t.integer "request_id", null: false
     t.string "status", default: "pending", null: false
diff --git a/app_charlie/spec/services/requests/cancel_service_spec.rb b/app_charlie/spec/services/requests/cancel_service_spec.rb
index 5458786..15153c5 100644
--- a/app_charlie/spec/services/requests/cancel_service_spec.rb
+++ b/app_charlie/spec/services/requests/cancel_service_spec.rb
@@ -53,5 +53,60 @@
       expect(result[:success]).to be false
       expect(result[:error]).to include("Cannot cancel request")
     end
+
+    context "cancellation fee (within 24 hours of scheduled time)" do
+      let!(:card) { create(:card, :default, client: client) }
+
+      context "when canceled within 24 hours of scheduled_at" do
+        let(:late_request) do
+          create(:request, :accepted, client: client, provider: provider,
+                 scheduled_at: 12.hours.from_now, amount_cents: 100_000)
+        end
+        let!(:payment) { create(:payment, :held, request: late_request, card: card, amount_cents: 100_000) }
+
+        it "charges a 50% cancellation fee" do
+          result = described_class.new(request: late_request, client: client, reason: "Emergency").call
+          expect(result[:success]).to be true
+          expect(payment.reload.cancellation_fee_cents).to eq(50_000)
+        end
+
+        it "partially refunds the payment" do
+          described_class.new(request: late_request, client: client, reason: "Emergency").call
+          expect(payment.reload.status).to eq("refunded")
+          expect(payment.reload.refund_amount_cents).to eq(50_000)
+        end
+      end
+
+      context "when canceled more than 24 hours before scheduled_at" do
+        let(:early_request) do
+          create(:request, :accepted, client: client, provider: provider,
+                 scheduled_at: 3.days.from_now, amount_cents: 100_000)
+        end
+        let!(:payment) { create(:payment, :held, request: early_request, card: card, amount_cents: 100_000) }
+
+        it "does not charge a cancellation fee" do
+          described_class.new(request: early_request, client: client, reason: "Changed plans").call
+          expect(payment.reload.cancellation_fee_cents).to eq(0)
+        end
+
+        it "fully refunds the payment" do
+          described_class.new(request: early_request, client: client, reason: "Changed plans").call
+          expect(payment.reload.status).to eq("refunded")
+        end
+      end
+
+      context "when canceled exactly at the 24-hour boundary" do
+        it "does not charge a cancellation fee" do
+          freeze_time do
+            boundary_request = create(:request, :accepted, client: client, provider: provider,
+                                      scheduled_at: 24.hours.from_now, amount_cents: 100_000)
+            payment = create(:payment, :held, request: boundary_request, card: card, amount_cents: 100_000)
+
+            described_class.new(request: boundary_request, client: client, reason: "Changed plans").call
+            expect(payment.reload.cancellation_fee_cents).to eq(0)
+          end
+        end
+      end
+    end
   end
 end
```
