# Experiment: e04-cancellation-fee
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e04-cancellation-fee/app_echo/opus/run-3

---

## Claude Output

All 148 tests pass. Here's a summary of the changes:

**Migration**: `cancellation_fee_cents` column already existed on `requests` and `payments` tables from a prior run.

**`app/services/requests/cancel_service.rb`** — Added late cancellation detection:
- If the booking is canceled within 24 hours of `scheduled_at`, a 50% fee (`amount_cents * 0.5`) is stored on the request and a partial refund is issued
- If canceled earlier than 24h, full refund as before

**`app/services/payment_gateway.rb`** — Added `partial_refund(payment, fee_cents:)`:
- Records the cancellation fee on the payment
- Refunds the payment (marking status as refunded)
- Logs the partial refund with both refund amount and fee

**`spec/services/requests/cancel_service_spec.rb`** — Added tests for:
- Early cancellation: full refund, no fee
- Late cancellation (12h before): 50% fee charged, partial refund
- Edge case (exactly 24h): fee applies
- Charged payment within 24h: fee based on request amount
- Payment log includes partial refund details

**`spec/services/payment_gateway_spec.rb`** — Added tests for `.partial_refund` (success, fee recording, logging, and failure for pending payments).

---

## Git Diff

```diff
diff --git a/app_echo/app/services/payment_gateway.rb b/app_echo/app/services/payment_gateway.rb
index be4203e..b3dbc7c 100644
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
+    refund_amount = @payment.amount_cents - fee_cents
+    @payment.update!(cancellation_fee_cents: fee_cents)
+    @payment.refund!
+    log("partial_refund", "payment_id=#{@payment.id} refund_amount=#{refund_amount} fee=#{fee_cents}")
+    { success: true }
+  end
+
   private
 
   def log(action, message)
diff --git a/app_echo/app/services/requests/cancel_service.rb b/app_echo/app/services/requests/cancel_service.rb
index 546ae94..9373e5c 100644
--- a/app_echo/app/services/requests/cancel_service.rb
+++ b/app_echo/app/services/requests/cancel_service.rb
@@ -1,5 +1,8 @@
 module Requests
   class CancelService
+    LATE_CANCELLATION_WINDOW = 24.hours
+    LATE_CANCELLATION_FEE_RATE = 0.5
+
     def initialize(request:, client:, reason:)
       @request = request
       @client = client
@@ -13,9 +16,7 @@ def call
       @request.cancel_reason = @reason
       @request.cancel!
 
-      if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
-      end
+      process_payment_refund
 
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
       { success: true, request: @request }
@@ -25,6 +26,22 @@ def call
 
     private
 
+    def process_payment_refund
+      return unless @request.payment && %w[held charged].include?(@request.payment.status)
+
+      if late_cancellation?
+        fee_cents = (@request.amount_cents * LATE_CANCELLATION_FEE_RATE).to_i
+        @request.update!(cancellation_fee_cents: fee_cents)
+        PaymentGateway.partial_refund(@request.payment, fee_cents: fee_cents)
+      else
+        PaymentGateway.refund(@request.payment)
+      end
+    end
+
+    def late_cancellation?
+      @request.scheduled_at <= Time.current + LATE_CANCELLATION_WINDOW
+    end
+
     def error(message)
       { success: false, error: message }
     end
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
diff --git a/app_echo/spec/services/payment_gateway_spec.rb b/app_echo/spec/services/payment_gateway_spec.rb
index 8b2e52c..cc3c2f0 100644
--- a/app_echo/spec/services/payment_gateway_spec.rb
+++ b/app_echo/spec/services/payment_gateway_spec.rb
@@ -112,4 +112,41 @@
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
+      it "updates payment status to refunded" do
+        PaymentGateway.partial_refund(payment, fee_cents: 175_000)
+        expect(payment.reload.status).to eq("refunded")
+      end
+
+      it "records the cancellation fee on the payment" do
+        PaymentGateway.partial_refund(payment, fee_cents: 175_000)
+        expect(payment.reload.cancellation_fee_cents).to eq(175_000)
+      end
+
+      it "writes to payment log" do
+        PaymentGateway.partial_refund(payment, fee_cents: 175_000)
+        expect(read_payment_log).to include("[PAYMENT] action=partial_refund")
+        expect(read_payment_log).to include("refund_amount=175000")
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
diff --git a/app_echo/spec/services/requests/cancel_service_spec.rb b/app_echo/spec/services/requests/cancel_service_spec.rb
index 5458786..03e9d13 100644
--- a/app_echo/spec/services/requests/cancel_service_spec.rb
+++ b/app_echo/spec/services/requests/cancel_service_spec.rb
@@ -4,7 +4,7 @@
   let(:client) { create(:client) }
   let(:other_client) { create(:client) }
   let(:provider) { create(:provider) }
-  let(:request) { create(:request, client: client, provider: provider) }
+  let(:request) { create(:request, client: client, provider: provider, scheduled_at: 3.days.from_now) }
 
   describe "#call" do
     it "cancels a pending request" do
@@ -14,20 +14,70 @@
     end
 
     it "cancels an accepted request" do
-      accepted_request = create(:request, :accepted, client: client, provider: provider)
+      accepted_request = create(:request, :accepted, client: client, provider: provider, scheduled_at: 3.days.from_now)
       result = described_class.new(request: accepted_request, client: client, reason: "Emergency").call
       expect(result[:success]).to be true
       expect(accepted_request.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when payment is held and canceled early (more than 24h before scheduled time)" do
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "fully refunds the held payment" do
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
+
+      it "does not charge a cancellation fee" do
+        described_class.new(request: request, client: client, reason: "Changed my mind").call
+        expect(request.reload.cancellation_fee_cents).to eq(0)
+      end
+    end
+
+    context "when canceled within 24 hours of scheduled time" do
+      let(:soon_request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: soon_request, card: card, amount_cents: 350_000) }
+
+      it "charges a 50% cancellation fee" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(soon_request.reload.cancellation_fee_cents).to eq(175_000)
+      end
+
+      it "partially refunds the payment" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(payment.reload.status).to eq("refunded")
+        expect(payment.reload.cancellation_fee_cents).to eq(175_000)
+      end
+
+      it "logs the partial refund" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(read_payment_log).to include("action=partial_refund")
+        expect(read_payment_log).to include("fee=175000")
+      end
+    end
+
+    context "when canceled exactly at 24 hours before scheduled time" do
+      let(:edge_request) { create(:request, client: client, provider: provider, scheduled_at: 24.hours.from_now) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: edge_request, card: card, amount_cents: 350_000) }
+
+      it "charges the cancellation fee" do
+        described_class.new(request: edge_request, client: client, reason: "Last minute").call
+        expect(edge_request.reload.cancellation_fee_cents).to eq(175_000)
+      end
+    end
+
+    context "when canceled with charged payment within 24 hours" do
+      let(:soon_request) { create(:request, client: client, provider: provider, scheduled_at: 6.hours.from_now, amount_cents: 200_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :charged, request: soon_request, card: card, amount_cents: 200_000) }
+
+      it "charges a 50% cancellation fee" do
+        described_class.new(request: soon_request, client: client, reason: "Emergency").call
+        expect(soon_request.reload.cancellation_fee_cents).to eq(100_000)
+      end
     end
 
     it "notifies the provider" do
```
