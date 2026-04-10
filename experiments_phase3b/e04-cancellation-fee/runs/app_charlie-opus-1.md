# Experiment: e04-cancellation-fee
# App: app_charlie | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_charlie/opus/run-1

---

## Claude Output

Implementation complete. Here's a summary of what was done:

**Changes made:**

1. **Migration** (`db/migrate/20260410120000_add_cancellation_fee_cents_to_requests.rb`) — Adds `cancellation_fee_cents` integer column (default 0) to the `requests` table.

2. **Request model** (`app/models/request.rb`) — Added two helper methods:
   - `late_cancellation?` — returns true if `scheduled_at` is within 24 hours of the current time
   - `cancellation_fee` — returns 50% of `amount_cents`

3. **CancelService** (`app/services/requests/cancel_service.rb`) — Updated cancellation logic:
   - **Late cancellation** (within 24h): records the fee on the request, updates the payment amount to 50%, and charges it
   - **Early cancellation** (more than 24h): full refund as before
   - Notification now includes the `cancellation_fee_cents` amount

4. **API response** (`app/controllers/api/requests_controller.rb`) — Added `cancellation_fee_cents` to the request detail JSON.

5. **Tests** (`spec/services/requests/cancel_service_spec.rb`) — Added 6 new test cases covering: early cancellation full refund, late cancellation fee charge, boundary condition (exactly 24h), late cancellation with held payment, late cancellation without payment, and fee amount in notifications.

All 112 tests pass.

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
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..feb2e9c 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -28,6 +28,16 @@ class Request < ApplicationRecord
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
 
+  LATE_CANCELLATION_WINDOW = 24.hours
+
+  def late_cancellation?
+    scheduled_at <= Time.current + LATE_CANCELLATION_WINDOW
+  end
+
+  def cancellation_fee
+    (amount_cents * 0.5).to_i
+  end
+
   aasm column: :state do
     state :pending, initial: true
     state :accepted
diff --git a/app_charlie/app/services/requests/cancel_service.rb b/app_charlie/app/services/requests/cancel_service.rb
index 546ae94..fc81df8 100644
--- a/app_charlie/app/services/requests/cancel_service.rb
+++ b/app_charlie/app/services/requests/cancel_service.rb
@@ -11,13 +11,17 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @request.cancel_reason = @reason
-      @request.cancel!
 
-      if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+      if @request.late_cancellation?
+        apply_cancellation_fee
+      else
+        full_refund
       end
 
-      NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
+      @request.cancel!
+
+      NotificationService.notify(@request.provider, :request_canceled,
+        request_id: @request.id, cancellation_fee_cents: @request.cancellation_fee_cents)
       { success: true, request: @request }
     rescue AASM::InvalidTransition
       error("Cannot cancel request in #{@request.state} state")
@@ -25,6 +29,24 @@ def call
 
     private
 
+    def apply_cancellation_fee
+      fee = @request.cancellation_fee
+      @request.cancellation_fee_cents = fee
+
+      payment = @request.payment
+      return unless payment && %w[held charged].include?(payment.status)
+
+      payment.update!(amount_cents: fee)
+      PaymentGateway.charge(payment) if payment.status == "held"
+    end
+
+    def full_refund
+      payment = @request.payment
+      return unless payment && %w[held charged].include?(payment.status)
+
+      PaymentGateway.refund(payment)
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_charlie/db/migrate/20260410120000_add_cancellation_fee_cents_to_requests.rb b/app_charlie/db/migrate/20260410120000_add_cancellation_fee_cents_to_requests.rb
new file mode 100644
index 0000000..d0fe13e
--- /dev/null
+++ b/app_charlie/db/migrate/20260410120000_add_cancellation_fee_cents_to_requests.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..8b688c2 100644
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
@@ -72,6 +72,7 @@
     t.datetime "accepted_at"
     t.integer "amount_cents", null: false
     t.text "cancel_reason"
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "client_id", null: false
     t.datetime "completed_at"
     t.datetime "created_at", null: false
diff --git a/app_charlie/spec/services/requests/cancel_service_spec.rb b/app_charlie/spec/services/requests/cancel_service_spec.rb
index 5458786..1e2e895 100644
--- a/app_charlie/spec/services/requests/cancel_service_spec.rb
+++ b/app_charlie/spec/services/requests/cancel_service_spec.rb
@@ -4,7 +4,7 @@
   let(:client) { create(:client) }
   let(:other_client) { create(:client) }
   let(:provider) { create(:provider) }
-  let(:request) { create(:request, client: client, provider: provider) }
+  let(:request) { create(:request, client: client, provider: provider, scheduled_at: 3.days.from_now) }
 
   describe "#call" do
     it "cancels a pending request" do
@@ -14,20 +14,68 @@
     end
 
     it "cancels an accepted request" do
-      accepted_request = create(:request, :accepted, client: client, provider: provider)
+      accepted_request = create(:request, :accepted, client: client, provider: provider, scheduled_at: 3.days.from_now)
       result = described_class.new(request: accepted_request, client: client, reason: "Emergency").call
       expect(result[:success]).to be true
       expect(accepted_request.reload.state).to eq("canceled")
     end
 
-    context "when payment is held" do
+    context "when canceled more than 24 hours before scheduled time" do
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment in full" do
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
+      let(:late_request) do
+        create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 100_000)
+      end
+
+      it "charges a 50% cancellation fee" do
+        result = described_class.new(request: late_request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(late_request.reload.cancellation_fee_cents).to eq(50_000)
+      end
+
+      context "with a held payment" do
+        let!(:card) { create(:card, :default, client: client) }
+        let!(:payment) { create(:payment, :held, request: late_request, card: card, amount_cents: 100_000) }
+
+        it "charges 50% of the booking amount" do
+          described_class.new(request: late_request, client: client, reason: "Last minute change").call
+          expect(payment.reload.amount_cents).to eq(50_000)
+          expect(payment.reload.status).to eq("charged")
+        end
+      end
+
+      context "without a payment" do
+        it "records the fee but does not attempt payment" do
+          result = described_class.new(request: late_request, client: client, reason: "Changed my mind").call
+          expect(result[:success]).to be true
+          expect(late_request.reload.cancellation_fee_cents).to eq(50_000)
+        end
+      end
+    end
+
+    context "when canceled exactly at the 24-hour boundary" do
+      let(:boundary_request) do
+        create(:request, client: client, provider: provider, scheduled_at: 24.hours.from_now, amount_cents: 100_000)
+      end
+
+      it "charges the cancellation fee" do
+        result = described_class.new(request: boundary_request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(boundary_request.reload.cancellation_fee_cents).to eq(50_000)
+      end
     end
 
     it "notifies the provider" do
@@ -35,6 +83,12 @@
       expect(read_notification_log).to include("event=request_canceled")
     end
 
+    it "includes cancellation fee in notification" do
+      late_request = create(:request, client: client, provider: provider, scheduled_at: 6.hours.from_now, amount_cents: 200_000)
+      described_class.new(request: late_request, client: client, reason: "Changed my mind").call
+      expect(read_notification_log).to include("cancellation_fee_cents=100000")
+    end
+
     it "fails without a reason" do
       result = described_class.new(request: request, client: client, reason: "").call
       expect(result[:success]).to be false
```
