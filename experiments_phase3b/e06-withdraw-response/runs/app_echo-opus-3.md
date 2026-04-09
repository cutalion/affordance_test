# Experiment: e06-withdraw-response
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e06-withdraw-response/app_echo/opus/run-3

---

## Claude Output

All 143 tests pass (including 6 new ones). Here's what I implemented:

**Feature: Provider can withdraw their response to an announcement**

A provider who responded to an announcement can withdraw that response while it's still in `pending` state (before the client accepts/declines).

**Changes:**

1. **`app/models/request.rb`** — Added `withdrawn` state, `withdraw` event (from `pending`), and `withdraw_reason` presence validation
2. **`app/services/requests/withdraw_service.rb`** — New service that validates ownership, ensures the request is an announcement response, requires a reason, transitions state, and notifies the client
3. **`app/controllers/api/announcements_controller.rb`** — Added `withdraw_response` action that takes `request_id` and `reason` params
4. **`config/routes.rb`** — Added `PATCH /api/announcements/:id/withdraw_response` route
5. **`spec/services/requests/withdraw_service_spec.rb`** — 6 tests covering happy path, notification, missing reason, non-announcement request, wrong provider, and already-accepted request
6. **`spec/factories/requests.rb`** — Added `:withdrawn` trait

**API usage:**
```
PATCH /api/announcements/:announcement_id/withdraw_response
Authorization: Bearer <provider_token>
{ "request_id": 123, "reason": "No longer available" }
```

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/announcements_controller.rb b/app_echo/app/controllers/api/announcements_controller.rb
index 5c0d2c6..d20a588 100644
--- a/app_echo/app/controllers/api/announcements_controller.rb
+++ b/app_echo/app/controllers/api/announcements_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class AnnouncementsController < BaseController
-    before_action :set_announcement, only: [:show, :publish, :close, :respond]
+    before_action :set_announcement, only: [:show, :publish, :close, :respond, :withdraw_response]
 
     def index
       announcements = Announcement.published.sorted.page(params[:page])
@@ -67,6 +67,30 @@ def respond
       end
     end
 
+    def withdraw_response
+      provider = current_provider!
+      return if performed?
+
+      request = @announcement.requests.find_by(id: params[:request_id])
+      return render_not_found unless request
+
+      if params[:reason].blank?
+        return render_unprocessable(["Reason is required"])
+      end
+
+      result = Requests::WithdrawService.new(
+        request: request,
+        provider: provider,
+        reason: params[:reason]
+      ).call
+
+      if result[:success]
+        render json: request_json(result[:request])
+      else
+        render json: { error: result[:error] }, status: :unprocessable_entity
+      end
+    end
+
     private
 
     def set_announcement
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
index da43a53..3a2ab9e 100644
--- a/app_echo/config/routes.rb
+++ b/app_echo/config/routes.rb
@@ -29,6 +29,7 @@
         patch :publish
         patch :close
         post :respond
+        patch :withdraw_response
       end
     end
   end
diff --git a/app_echo/spec/factories/requests.rb b/app_echo/spec/factories/requests.rb
index 4620d0c..aa29bc3 100644
--- a/app_echo/spec/factories/requests.rb
+++ b/app_echo/spec/factories/requests.rb
@@ -47,6 +47,13 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :withdrawn do
+      state { "withdrawn" }
+      withdraw_reason { "No longer available" }
+      withdrawn_at { Time.current }
+      announcement { association :announcement, :published }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_echo/spec/services/requests/withdraw_service_spec.rb b/app_echo/spec/services/requests/withdraw_service_spec.rb
new file mode 100644
index 0000000..c14982b
--- /dev/null
+++ b/app_echo/spec/services/requests/withdraw_service_spec.rb
@@ -0,0 +1,62 @@
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
+        result = described_class.new(request: request, provider: provider, reason: "No longer available").call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_withdrawn
+        expect(request.withdraw_reason).to eq("No longer available")
+        expect(request.withdrawn_at).to be_present
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, reason: "No longer available").call
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
+      let(:request) { create(:request, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, reason: "Changed my mind").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Can only withdraw responses to announcements")
+      end
+    end
+
+    context "when request belongs to another provider" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: other_provider, reason: "Changed my mind").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "when request is already accepted" do
+      let(:request) { create(:request, :accepted, :announcement_response, provider: provider, announcement: announcement) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, reason: "Changed my mind").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot withdraw request in accepted state")
+      end
+    end
+  end
+end
```
