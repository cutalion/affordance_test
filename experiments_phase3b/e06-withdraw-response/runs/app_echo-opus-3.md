# Experiment: e06-withdraw-response
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e06-withdraw-response/app_echo/opus/run-3

---

## Claude Output

All 148 specs pass. Here's a summary of what was implemented:

**Migration** — Added `withdraw_reason` (text) and `withdrawn_at` (datetime) columns to the `requests` table.

**Model** (`app/models/request.rb`) — Added `withdrawn` state, `withdraw` event (transitions from `pending` to `withdrawn`, sets `withdrawn_at`), and validation requiring `withdraw_reason` when withdrawn.

**Service** (`app/services/requests/withdraw_service.rb`) — Validates that:
- The provider owns the request
- The request is a response to an announcement (not a direct request)
- A reason is provided
- Notifies the client with a `response_withdrawn` event

**Controller** (`app/controllers/api/requests_controller.rb`) — Added `withdraw` action, exposed `withdraw_reason` and `withdrawn_at` in the JSON response.

**Route** — `PATCH /api/requests/:id/withdraw` with `reason` parameter.

**Specs** — Model specs for the withdraw state/validation/transitions, and service specs covering the happy path, missing reason, non-announcement requests, wrong provider, and already-accepted requests.

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..45dd46f 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :withdraw]
 
     def index
       requests = scoped_requests
@@ -104,6 +104,22 @@ def reject
       handle_service_result(result)
     end
 
+    def withdraw
+      provider = current_provider!
+      return if performed?
+
+      if params[:reason].blank?
+        return render_unprocessable(["Reason is required"])
+      end
+
+      result = Requests::WithdrawService.new(
+        request: @request,
+        provider: provider,
+        reason: params[:reason]
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -156,7 +172,9 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        withdraw_reason: request.withdraw_reason,
         accepted_at: request.accepted_at,
+        withdrawn_at: request.withdrawn_at,
         expired_at: request.expired_at,
         started_at: request.started_at,
         completed_at: request.completed_at,
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..763e8df 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -15,6 +15,7 @@ class Request < ApplicationRecord
   validates :decline_reason, presence: true, if: -> { declined? }
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :withdraw_reason, presence: true, if: -> { withdrawn? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -38,6 +39,7 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
+    state :withdrawn
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -78,5 +80,12 @@ class Request < ApplicationRecord
     event :reject do
       transitions from: [:accepted, :in_progress], to: :rejected
     end
+
+    event :withdraw do
+      transitions from: :pending, to: :withdrawn
+      after do
+        update!(withdrawn_at: Time.current)
+      end
+    end
   end
 end
diff --git a/app_echo/app/services/requests/withdraw_service.rb b/app_echo/app/services/requests/withdraw_service.rb
new file mode 100644
index 0000000..017a745
--- /dev/null
+++ b/app_echo/app/services/requests/withdraw_service.rb
@@ -0,0 +1,29 @@
+module Requests
+  class WithdrawService
+    def initialize(request:, provider:, reason:)
+      @request = request
+      @provider = provider
+      @reason = reason
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Can only withdraw responses to announcements") unless @request.announcement_id.present?
+      return error("Withdraw reason is required") if @reason.blank?
+
+      @request.withdraw_reason = @reason
+      @request.withdraw!
+
+      NotificationService.notify(@request.client, :response_withdrawn, request_id: @request.id, announcement_id: @request.announcement_id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot withdraw request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_echo/config/routes.rb b/app_echo/config/routes.rb
index da43a53..ba3a117 100644
--- a/app_echo/config/routes.rb
+++ b/app_echo/config/routes.rb
@@ -18,6 +18,7 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :withdraw
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/app_echo/db/migrate/20260410133438_add_withdraw_fields_to_requests.rb b/app_echo/db/migrate/20260410133438_add_withdraw_fields_to_requests.rb
new file mode 100644
index 0000000..8fa67fd
--- /dev/null
+++ b/app_echo/db/migrate/20260410133438_add_withdraw_fields_to_requests.rb
@@ -0,0 +1,6 @@
+class AddWithdrawFieldsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :withdraw_reason, :text
+    add_column :requests, :withdrawn_at, :datetime
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..4f48423 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_133438) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -108,6 +108,8 @@
     t.datetime "started_at"
     t.string "state", default: "pending", null: false
     t.datetime "updated_at", null: false
+    t.text "withdraw_reason"
+    t.datetime "withdrawn_at"
     t.index ["announcement_id"], name: "index_requests_on_announcement_id"
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
diff --git a/app_echo/spec/factories/requests.rb b/app_echo/spec/factories/requests.rb
index 4620d0c..cf3d710 100644
--- a/app_echo/spec/factories/requests.rb
+++ b/app_echo/spec/factories/requests.rb
@@ -47,6 +47,13 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :withdrawn do
+      state { "withdrawn" }
+      withdraw_reason { "Changed my mind" }
+      withdrawn_at { Time.current }
+      announcement { association :announcement, :published }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_echo/spec/models/request_spec.rb b/app_echo/spec/models/request_spec.rb
index a9aece5..9548ffb 100644
--- a/app_echo/spec/models/request_spec.rb
+++ b/app_echo/spec/models/request_spec.rb
@@ -51,6 +51,14 @@
         expect(request.errors[:reject_reason]).to be_present
       end
     end
+
+    context "when withdrawn" do
+      it "requires withdraw_reason" do
+        request = build(:request, :withdrawn, withdraw_reason: nil)
+        expect(request).not_to be_valid
+        expect(request.errors[:withdraw_reason]).to be_present
+      end
+    end
   end
 
   describe "state machine" do
@@ -180,6 +188,27 @@
         expect { request.reject! }.to raise_error(AASM::InvalidTransition)
       end
     end
+
+    describe "withdraw event" do
+      it "transitions from pending to withdrawn" do
+        request.update!(withdraw_reason: "Changed my mind")
+        request.withdraw!
+        expect(request).to be_withdrawn
+      end
+
+      it "sets withdrawn_at timestamp" do
+        freeze_time do
+          request.update!(withdraw_reason: "Changed my mind")
+          request.withdraw!
+          expect(request.reload.withdrawn_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "cannot withdraw from accepted" do
+        request.accept!
+        expect { request.withdraw! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/app_echo/spec/services/requests/withdraw_service_spec.rb b/app_echo/spec/services/requests/withdraw_service_spec.rb
new file mode 100644
index 0000000..b0a7f72
--- /dev/null
+++ b/app_echo/spec/services/requests/withdraw_service_spec.rb
@@ -0,0 +1,68 @@
+require "rails_helper"
+
+RSpec.describe Requests::WithdrawService do
+  let(:provider) { create(:provider) }
+  let(:announcement) { create(:announcement, :published) }
+  let(:request) { create(:request, :announcement_response, provider: provider, announcement: announcement) }
+
+  describe "#call" do
+    context "with correct provider and reason" do
+      it "withdraws the request" do
+        result = described_class.new(request: request, provider: provider, reason: "Found another job").call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_withdrawn
+        expect(request.withdraw_reason).to eq("Found another job")
+      end
+
+      it "sets withdrawn_at timestamp" do
+        freeze_time do
+          described_class.new(request: request, provider: provider, reason: "Found another job").call
+          expect(request.reload.withdrawn_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, reason: "Found another job").call
+        expect(read_notification_log).to include("event=response_withdrawn")
+      end
+    end
+
+    context "without reason" do
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, reason: nil).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Withdraw reason is required")
+      end
+    end
+
+    context "when request is not linked to an announcement" do
+      let(:direct_request) { create(:request, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: direct_request, provider: provider, reason: "Changed mind").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Can only withdraw responses to announcements")
+      end
+    end
+
+    context "when provider does not own the request" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: other_provider, reason: "Changed mind").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "when request is already accepted" do
+      let(:accepted_request) { create(:request, :accepted, :announcement_response, provider: provider, announcement: announcement) }
+
+      it "returns error" do
+        result = described_class.new(request: accepted_request, provider: provider, reason: "Changed mind").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot withdraw request in accepted state")
+      end
+    end
+  end
+end
```
