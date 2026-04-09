# Experiment: e04-cancellation-fee
# App: app_charlie | Model: opus | Run: 1
# Branch: debt_experiment/e04-cancellation-fee/app_charlie/opus/run-1

---

## Claude Output

All 109 tests pass. Here's a summary of the changes:

**Migration** — Added `cancellation_fee_cents` (integer, default 0) to `requests` table.

**Request model** — Added `LATE_CANCELLATION_WINDOW` (24 hours), `LATE_CANCELLATION_FEE_RATE` (0.5), `late_cancellation?`, and `calculate_cancellation_fee` methods.

**CancelService** — When a booking is cancelled within 24 hours of `scheduled_at`:
- Sets `cancellation_fee_cents` to 50% of `amount_cents`
- If a held payment exists, updates its amount to the fee and charges it (instead of refunding)
- If cancelled more than 24h before, refunds fully as before

**API response** — `cancellation_fee_cents` is now included in the request detail JSON.

**Tests** — Added specs for late cancellation (fee calculation, payment charging) and early cancellation (no fee).

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
index 4a4d28a..988ad5d 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -15,6 +15,9 @@ class Request < ApplicationRecord
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
 
+  LATE_CANCELLATION_WINDOW = 24.hours
+  LATE_CANCELLATION_FEE_RATE = 0.5
+
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
   scope :by_state, ->(state) { where(state: state) if state.present? }
@@ -28,6 +31,14 @@ class Request < ApplicationRecord
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
 
+  def late_cancellation?
+    scheduled_at <= Time.current + LATE_CANCELLATION_WINDOW
+  end
+
+  def calculate_cancellation_fee
+    (amount_cents * LATE_CANCELLATION_FEE_RATE).to_i
+  end
+
   aasm column: :state do
     state :pending, initial: true
     state :accepted
diff --git a/app_charlie/app/services/requests/cancel_service.rb b/app_charlie/app/services/requests/cancel_service.rb
index 546ae94..c98cdb5 100644
--- a/app_charlie/app/services/requests/cancel_service.rb
+++ b/app_charlie/app/services/requests/cancel_service.rb
@@ -11,12 +11,15 @@ def call
       return error("Cancel reason is required") if @reason.blank?
 
       @request.cancel_reason = @reason
-      @request.cancel!
 
-      if @request.payment && %w[held charged].include?(@request.payment.status)
-        PaymentGateway.refund(@request.payment)
+      if @request.late_cancellation?
+        @request.cancellation_fee_cents = @request.calculate_cancellation_fee
       end
 
+      @request.cancel!
+
+      handle_payment
+
       NotificationService.notify(@request.provider, :request_canceled, request_id: @request.id)
       { success: true, request: @request }
     rescue AASM::InvalidTransition
@@ -25,6 +28,18 @@ def call
 
     private
 
+    def handle_payment
+      payment = @request.payment
+      return unless payment && %w[held charged].include?(payment.status)
+
+      if @request.cancellation_fee_cents > 0
+        payment.update!(amount_cents: @request.cancellation_fee_cents)
+        PaymentGateway.charge(payment) if payment.status == "held"
+      else
+        PaymentGateway.refund(payment)
+      end
+    end
+
     def error(message)
       { success: false, error: message }
     end
diff --git a/app_charlie/db/migrate/20260409154618_add_cancellation_fee_cents_to_requests.rb b/app_charlie/db/migrate/20260409154618_add_cancellation_fee_cents_to_requests.rb
new file mode 100644
index 0000000..d0fe13e
--- /dev/null
+++ b/app_charlie/db/migrate/20260409154618_add_cancellation_fee_cents_to_requests.rb
@@ -0,0 +1,5 @@
+class AddCancellationFeeCentsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :cancellation_fee_cents, :integer, default: 0, null: false
+  end
+end
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
index 5458786..d4fec9b 100644
--- a/app_charlie/spec/services/requests/cancel_service_spec.rb
+++ b/app_charlie/spec/services/requests/cancel_service_spec.rb
@@ -24,12 +24,38 @@
       let!(:card) { create(:card, :default, client: client) }
       let!(:payment) { create(:payment, :held, request: request, card: card) }
 
-      it "refunds the held payment" do
+      it "refunds the held payment when cancelled early" do
         described_class.new(request: request, client: client, reason: "Changed my mind").call
         expect(payment.reload.status).to eq("refunded")
       end
     end
 
+    context "when cancelled within 24 hours of scheduled time" do
+      let(:soon_request) { create(:request, client: client, provider: provider, scheduled_at: 12.hours.from_now, amount_cents: 200_000) }
+      let!(:card) { create(:card, :default, client: client) }
+      let!(:payment) { create(:payment, :held, request: soon_request, card: card, amount_cents: 200_000) }
+
+      it "charges a 50% cancellation fee" do
+        result = described_class.new(request: soon_request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(soon_request.reload.cancellation_fee_cents).to eq(100_000)
+      end
+
+      it "charges the held payment for the fee amount" do
+        described_class.new(request: soon_request, client: client, reason: "Changed my mind").call
+        expect(payment.reload.status).to eq("charged")
+        expect(payment.reload.amount_cents).to eq(100_000)
+      end
+    end
+
+    context "when cancelled more than 24 hours before scheduled time" do
+      it "does not charge a cancellation fee" do
+        result = described_class.new(request: request, client: client, reason: "Changed my mind").call
+        expect(result[:success]).to be true
+        expect(request.reload.cancellation_fee_cents).to eq(0)
+      end
+    end
+
     it "notifies the provider" do
       described_class.new(request: request, client: client, reason: "Changed my mind").call
       expect(read_notification_log).to include("event=request_canceled")
```
