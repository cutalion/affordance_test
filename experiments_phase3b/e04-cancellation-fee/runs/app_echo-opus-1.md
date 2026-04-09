# Experiment: e04-cancellation-fee
# App: app_echo | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_echo/opus/run-1

---

## Claude Output

All 149 tests pass. Here's a summary of the changes:

**Migration**: Added `cancellation_fee_cents` (integer, default 0) to `requests` table.

**`PaymentGateway`** (`app/services/payment_gateway.rb`): Added `.partial_refund(payment, fee_cents:)` — reduces the payment amount by the fee, marks as refunded, and logs with fee details.

**`Requests::CancelService`** (`app/services/requests/cancel_service.rb`): When a payment exists and is held/charged:
- If `scheduled_at` is **less than 24 hours** away → charges 50% cancellation fee via partial refund, records `cancellation_fee_cents` on the request
- If **24 hours or more** away → full refund as before

**Tests**: 9 new tests covering: fee charged within 24h, fee recorded on payment, partial refund logged, no fee when >24h, full refund when >24h, exact 24h boundary (no fee), and just-under-24h (fee charged).

---

## Git Diff

```diff
diff --git a/app_echo/app/services/payment_gateway.rb b/app_echo/app/services/payment_gateway.rb
index be4203e..7008054 100644
--- a/app_echo/app/services/payment_gateway.rb
+++ b/app_echo/app/services/payment_gateway.rb
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
+    refunded_cents = @payment.amount_cents - fee_cents
+    @payment.update!(amount_cents: refunded_cents)
+    @payment.refund!
+    log("partial_refund", "payment_id=#{@payment.id} fee=#{fee_cents} refunded=#{refunded_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_echo/app/services/requests/cancel_service.rb b/app_echo/app/services/requests/cancel_service.rb
index 546ae94..41111b7 100644
--- a/app_echo/app/services/requests/cancel_service.rb
+++ b/app_echo/app/services/requests/cancel_service.rb
@@ -13,9 +13,7 @@ def call
       @request.cancel_reason = @reason
       @request.cancel!
 
-      if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
-      end
+      process_refund if @request.payment && %w[held charged].include?(@request.payment.status)
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
       { success: true, request: @request }
@@ -25,6 +23,20 @@ def call
 
     private
 
+    def process_refund
+      if within_24_hours?
+        fee_cents = @request.amount_cents / 2
+        @request.update!(cancellation_fee_cents: fee_cents)
+        PaymentGateway.partial_refund(@request.payment, fee_cents: fee_cents)
+      else
+        PaymentGateway.refund(@request.payment)
+      end
+    end
+
+    def within_24_hours?
+      (@request.scheduled_at - Time.current) < 24.hours
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_echo/db/migrate/20260409190854_add_cancellation_fee_cents_to_requests.rb b/app_echo/db/migrate/20260409190854_add_cancellation_fee_cents_to_requests.rb
new file mode 100644
index 0000000..d0fe13e
--- /dev/null
+++ b/app_echo/db/migrate/20260409190854_add_cancellation_fee_cents_to_requests.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index c2c99cb..3ad379f 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_084335) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_190854) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -91,8 +91,10 @@
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
@@ -101,6 +103,7 @@
     t.string "location"
     t.text "notes"
     t.integer "proposed_amount_cents"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.string "recurring_group_id"
     t.integer "recurring_index"
diff --git a/app_echo/spec/services/payment_gateway_spec.rb b/app_echo/spec/services/payment_gateway_spec.rb
index 8b2e52c..3296d14 100644
--- a/app_echo/spec/services/payment_gateway_spec.rb
+++ b/app_echo/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,41 @@
       end
     end
   end
+
+  describe ".partial_refund" do
+    let(:card) { create(:card, :default, client: client) }
+    let(:payment) { create(:payment, :held, request: request, card: card, amount_cents: 400_000) }
+
+    it "returns success" do
+      result = PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+      expect(result[:success]).to be true
+    end
+
+    it "reduces the payment amount by the fee" do
+      PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+      expect(payment.reload.amount_cents).to eq(200_000)
+    end
+
+    it "updates payment status to refunded" do
+      PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+      expect(payment.reload.status).to eq("refunded")
+    end
+
+    it "writes to payment log with fee details" do
+      PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+      log = read_payment_log
+      expect(log).to include("[PAYMENT] action=partial_refund")
+      expect(log).to include("fee=200000")
+      expect(log).to include("refunded=200000")
+    end
+
+    context "when payment is not held or charged" do
+      let(:payment) { create(:payment, request: request, amount_cents: 400_000) }
+
+      it "returns failure" do
+        result = PaymentGateway.partial_refund(payment, fee_cents: 200_000)
+        expect(result[:success]).to be false
+      end
+    end
+  end
 end
diff --git a/app_echo/spec/services/requests/cancel_service_spec.rb b/app_echo/spec/services/requests/cancel_service_spec.rb
index 5458786..c6b3e97 100644
--- a/app_echo/spec/services/requests/cancel_service_spec.rb
+++ b/app_echo/spec/services/requests/cancel_service_spec.rb
@@ -53,5 +53,74 @@
       expect(result[:success]).to be false
       expect(result[:error]).to include("Cannot cancel request")
     end
+
+    context "cancellation fee (within 24 hours of scheduled time)" do
+      let!(:card) { create(:card, :default, client: client) }
+      let(:soon_request) do
+        create(:request, :accepted, client: client, provider: provider,
+               scheduled_at: 12.hours.from_now, amount_cents: 400_000)
+      end
+      let!(:soon_payment) { create(:payment, :held, request: soon_request, card: card, amount_cents: 400_000) }
+
+      it "charges a 50% cancellation fee" do
+        result = described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(result[:success]).to be true
+        expect(soon_request.reload.cancellation_fee_cents).to eq(200_000)
+      end
+
+      it "records the fee in the payment" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(soon_payment.reload.status).to eq("refunded")
+        expect(soon_payment.reload.amount_cents).to eq(200_000)
+      end
+
+      it "logs a partial refund" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(read_payment_log).to include("action=partial_refund")
+        expect(read_payment_log).to include("fee=200000")
+      end
+    end
+
+    context "cancellation without fee (more than 24 hours before scheduled time)" do
+      let!(:card) { create(:card, :default, client: client) }
+      let(:future_request) do
+        create(:request, :accepted, client: client, provider: provider,
+               scheduled_at: 3.days.from_now, amount_cents: 400_000)
+      end
+      let!(:future_payment) { create(:payment, :held, request: future_request, card: card, amount_cents: 400_000) }
+
+      it "does not charge a cancellation fee" do
+        described_class.new(request: future_request, client: client, reason: "Changed plans").call
+        expect(future_request.reload.cancellation_fee_cents).to eq(0)
+      end
+
+      it "fully refunds the payment" do
+        described_class.new(request: future_request, client: client, reason: "Changed plans").call
+        expect(future_payment.reload.status).to eq("refunded")
+        expect(future_payment.reload.amount_cents).to eq(400_000)
+      end
+    end
+
+    context "cancellation fee at exactly 24 hours boundary" do
+      let!(:card) { create(:card, :default, client: client) }
+
+      it "does not charge fee when exactly 24 hours away" do
+        freeze_time do
+          boundary_request = create(:request, :accepted, client: client, provider: provider,
+                                    scheduled_at: 24.hours.from_now, amount_cents: 400_000)
+          create(:payment, :held, request: boundary_request, card: card, amount_cents: 400_000)
+          described_class.new(request: boundary_request, client: client, reason: "Plans changed").call
+          expect(boundary_request.reload.cancellation_fee_cents).to eq(0)
+        end
+      end
+
+      it "charges fee when just under 24 hours away" do
+        close_request = create(:request, :accepted, client: client, provider: provider,
+                               scheduled_at: 23.hours.from_now, amount_cents: 400_000)
+        create(:payment, :held, request: close_request, card: card, amount_cents: 400_000)
+        described_class.new(request: close_request, client: client, reason: "Plans changed").call
+        expect(close_request.reload.cancellation_fee_cents).to eq(200_000)
+      end
+    end
   end
 end
```
