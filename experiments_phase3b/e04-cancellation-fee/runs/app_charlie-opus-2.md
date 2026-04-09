# Experiment: e04-cancellation-fee
# App: app_charlie | Model: opus | Run: 2
# Branch: debt_experiment/e04-cancellation-fee/app_charlie/opus/run-2

---

## Claude Output

All 109 specs pass. Here's what I implemented:

**Cancellation fee: 50% charge when canceled within 24 hours of scheduled time**

**Changes:**

1. **`app/services/requests/cancel_service.rb`** — Added `late_cancellation?` check (scheduled_at ≤ 24 hours away). When true, sets `cancellation_fee_cents` to 50% of the booking amount. If a held payment exists, it reduces the payment amount to the fee and charges it instead of refunding. Early cancellations still get a full refund.

2. **`app/controllers/api/requests_controller.rb`** — Added `cancellation_fee_cents` to the API response.

3. **`spec/services/requests/cancel_service_spec.rb`** — Added tests for: fee charged within 24h, no fee beyond 24h, held payment charged at fee amount instead of refunded.

The `cancellation_fee_cents` column already existed in the database from a prior migration run.

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..e6dd005 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -157,6 +157,7 @@ def request_detail_json(request)
         currency: request.currency,
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
+        cancellation_fee_cents: request.cancellation_fee_cents,
         reject_reason: request.reject_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
diff --git a/app_charlie/app/services/requests/cancel_service.rb b/app_charlie/app/services/requests/cancel_service.rb
index 546ae94..80cc151 100644
--- a/app_charlie/app/services/requests/cancel_service.rb
+++ b/app_charlie/app/services/requests/cancel_service.rb
@@ -11,12 +11,15 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @request.cancel_reason = @reason
-      @request.cancel!
 
-      if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+      if late_cancellation?
+        @request.cancellation_fee_cents = (@request.amount_cents * 0.5).round
       end
 
+      @request.cancel!
+
+      handle_payment
+
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
       { success: true, request: @request }
     rescue AASM::InvalidTransition
@@ -25,6 +28,25 @@ def call
 
     private
 
+    def late_cancellation?
+      @request.scheduled_at <= 24.hours.from_now
+    end
+
+    def handle_payment
+      payment = @request.payment
+      return unless payment && %w[held charged].include?(payment.status)
+
+      if @request.cancellation_fee_cents > 0
+        payment.update!(
+          amount_cents: @request.cancellation_fee_cents,
+          fee_cents: @request.cancellation_fee_cents
+        )
+        PaymentGateway.charge(payment) if payment.status == "held"
+      else
+        PaymentGateway.refund(payment)
+      end
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 4757a0b..dfa33e7 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_081113) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_154618) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -72,6 +72,7 @@
     t.datetime "accepted_at"
     t.integer "amount_cents", null: false
     t.text "cancel_reason"
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "client_id", null: false
     t.datetime "completed_at"
     t.datetime "created_at", null: false
@@ -81,6 +82,8 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_note"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.string "recurring_group_id"
     t.integer "recurring_index"
diff --git a/app_charlie/spec/services/requests/cancel_service_spec.rb b/app_charlie/spec/services/requests/cancel_service_spec.rb
index 5458786..dc0a826 100644
--- a/app_charlie/spec/services/requests/cancel_service_spec.rb
+++ b/app_charlie/spec/services/requests/cancel_service_spec.rb
@@ -24,12 +24,43 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment when canceled early" do
+        request.update!(scheduled_at: 48.hours.from_now)
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
     end
 
+    context "cancellation fee" do
+      let(:request) { create(:request, client: client, provider: provider, amount_cents: 10_000, scheduled_at: 12.hours.from_now) }
+
+      it "charges 50% fee when canceled within 24 hours of scheduled time" do
+        result = described_class.new(request: request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(request.reload.cancellation_fee_cents).to eq(5_000)
+      end
+
+      it "does not charge fee when canceled more than 24 hours before" do
+        request.update!(scheduled_at: 48.hours.from_now)
+        result = described_class.new(request: request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(request.reload.cancellation_fee_cents).to eq(0)
+      end
+
+      context "with held payment" do
+        let!(:card) { create(:card, :default, client: client) }
+        let!(:payment) { create(:payment, :held, request: request, card: card, amount_cents: 10_000) }
+
+        it "charges the fee amount instead of refunding" do
+          described_class.new(request: request, client: client, reason: "Last minute cancel").call
+          payment.reload
+          expect(payment.status).to eq("charged")
+          expect(payment.amount_cents).to eq(5_000)
+          expect(payment.fee_cents).to eq(5_000)
+        end
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: request, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
