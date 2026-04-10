# Experiment: e06-withdraw-response
# App: app_echo | Model: opus | Run: 2
# Branch: debt_experiment/e06-withdraw-response/app_echo/opus/run-2

---

## Claude Output

All 144 tests pass (including 7 new ones). Here's a summary of what was implemented:

**Feature: Provider can withdraw their response to an announcement**

**Changes:**

1. **Migration** (`db/migrate/20260410133115_add_withdrawn_at_to_requests.rb`) — adds `withdrawn_at` datetime column to requests table

2. **Model** (`app/models/request.rb`) — added `withdrawn` state and `withdraw` event (transitions from `pending` to `withdrawn`, sets `withdrawn_at` timestamp)

3. **Service** (`app/services/requests/withdraw_service.rb`) — `Requests::WithdrawService` that:
   - Validates the provider owns the request
   - Validates the request is an announcement response (not a direct invitation)
   - Transitions the request to `withdrawn` state
   - Notifies the client about the withdrawal

4. **Controller** (`app/controllers/api/requests_controller.rb`) — added `withdraw` action, requires provider auth

5. **Route** (`config/routes.rb`) — `PATCH /api/requests/:id/withdraw`

6. **Specs** (`spec/services/requests/withdraw_service_spec.rb`) — 7 test cases covering happy path, wrong provider, non-announcement request, already accepted, and already withdrawn scenarios

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..a67f3a4 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :withdraw]
 
     def index
       requests = scoped_requests
@@ -104,6 +104,17 @@ def reject
       handle_service_result(result)
     end
 
+    def withdraw
+      provider = current_provider!
+      return if performed?
+
+      result = Requests::WithdrawService.new(
+        request: @request,
+        provider: provider
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -160,6 +171,7 @@ def request_detail_json(request)
         expired_at: request.expired_at,
         started_at: request.started_at,
         completed_at: request.completed_at,
+        withdrawn_at: request.withdrawn_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
         payment: request.payment ? {
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..1512893 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -38,6 +38,7 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
+    state :withdrawn
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -78,5 +79,12 @@ class Request < ApplicationRecord
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
index 0000000..b0772fa
--- /dev/null
+++ b/app_echo/app/services/requests/withdraw_service.rb
@@ -0,0 +1,26 @@
+module Requests
+  class WithdrawService
+    def initialize(request:, provider:)
+      @request = request
+      @provider = provider
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Can only withdraw responses to announcements") unless @request.announcement.present?
+
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
diff --git a/app_echo/db/migrate/20260410133115_add_withdrawn_at_to_requests.rb b/app_echo/db/migrate/20260410133115_add_withdrawn_at_to_requests.rb
new file mode 100644
index 0000000..1845c73
--- /dev/null
+++ b/app_echo/db/migrate/20260410133115_add_withdrawn_at_to_requests.rb
@@ -0,0 +1,5 @@
+class AddWithdrawnAtToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :withdrawn_at, :datetime
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..fdf8bfb 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_133115) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -108,6 +108,7 @@
     t.datetime "started_at"
     t.string "state", default: "pending", null: false
     t.datetime "updated_at", null: false
+    t.datetime "withdrawn_at"
     t.index ["announcement_id"], name: "index_requests_on_announcement_id"
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
diff --git a/app_echo/spec/factories/requests.rb b/app_echo/spec/factories/requests.rb
index 4620d0c..5dd1a42 100644
--- a/app_echo/spec/factories/requests.rb
+++ b/app_echo/spec/factories/requests.rb
@@ -47,6 +47,11 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :withdrawn do
+      state { "withdrawn" }
+      withdrawn_at { Time.current }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_echo/spec/services/requests/withdraw_service_spec.rb b/app_echo/spec/services/requests/withdraw_service_spec.rb
new file mode 100644
index 0000000..782ad21
--- /dev/null
+++ b/app_echo/spec/services/requests/withdraw_service_spec.rb
@@ -0,0 +1,80 @@
+require "rails_helper"
+
+RSpec.describe Requests::WithdrawService do
+  let(:client) { create(:client) }
+  let(:announcement) { create(:announcement, :published, client: client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request,
+      client: client,
+      provider: provider,
+      announcement: announcement,
+      response_message: "I can help",
+      proposed_amount_cents: 400_000
+    )
+  end
+
+  describe "#call" do
+    context "with correct provider and pending announcement response" do
+      it "withdraws the response" do
+        result = described_class.new(request: request, provider: provider).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_withdrawn
+      end
+
+      it "sets withdrawn_at timestamp" do
+        freeze_time do
+          described_class.new(request: request, provider: provider).call
+          expect(request.reload.withdrawn_at).to eq(Time.current)
+        end
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider).call
+        expect(read_notification_log).to include("event=response_withdrawn")
+      end
+    end
+
+    context "with wrong provider" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: other_provider).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "when request is not an announcement response" do
+      let(:direct_request) { create(:request, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: direct_request, provider: provider).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Can only withdraw responses to announcements")
+      end
+    end
+
+    context "when request is already accepted" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot withdraw request in accepted state")
+      end
+    end
+
+    context "when request is already withdrawn" do
+      before do
+        request.withdraw!
+      end
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot withdraw request in withdrawn state")
+      end
+    end
+  end
+end
```
