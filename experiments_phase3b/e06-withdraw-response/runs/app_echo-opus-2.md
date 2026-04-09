# Experiment: e06-withdraw-response
# App: app_echo | Model: opus | Run: 2
# Branch: debt_experiment/e06-withdraw-response/app_echo/opus/run-2

---

## Claude Output

All done. 142 specs passing, 0 failures. Here's what was implemented:

**Model** (`app/models/request.rb`):
- Added `withdrawn` state and `withdraw` event (transitions from `pending` only)
- Sets `withdrawn_at` timestamp on transition
- Added validation requiring `withdraw_reason` when withdrawn

**Service** (`app/services/requests/withdraw_service.rb`):
- Follows the same pattern as `DeclineService` — verifies ownership, requires reason, transitions state, notifies client

**Controller** (`app/controllers/api/requests_controller.rb`):
- Added `withdraw` action requiring provider auth and a reason parameter
- Added `withdraw_reason` and `withdrawn_at` to the detail JSON response

**Route**: `PATCH /api/requests/:id/withdraw`

**Spec** (`spec/services/requests/withdraw_service_spec.rb`): 5 tests covering success, notification, missing reason, wrong provider, and invalid state transition.

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
index 0000000..aee56dc
--- /dev/null
+++ b/app_echo/app/services/requests/withdraw_service.rb
@@ -0,0 +1,28 @@
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
+      return error("Withdraw reason is required") if @reason.blank?
+
+      @request.withdraw_reason = @reason
+      @request.withdraw!
+
+      NotificationService.notify(@request.client, :response_withdrawn, request_id: @request.id)
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
diff --git a/app_echo/spec/factories/requests.rb b/app_echo/spec/factories/requests.rb
index 4620d0c..e54d657 100644
--- a/app_echo/spec/factories/requests.rb
+++ b/app_echo/spec/factories/requests.rb
@@ -47,6 +47,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :withdrawn do
+      state { "withdrawn" }
+      withdraw_reason { "No longer available" }
+      withdrawn_at { Time.current }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_echo/spec/services/requests/withdraw_service_spec.rb b/app_echo/spec/services/requests/withdraw_service_spec.rb
new file mode 100644
index 0000000..44715a2
--- /dev/null
+++ b/app_echo/spec/services/requests/withdraw_service_spec.rb
@@ -0,0 +1,58 @@
+require "rails_helper"
+
+RSpec.describe Requests::WithdrawService do
+  let(:provider) { create(:provider) }
+  let(:client) { create(:client) }
+  let(:announcement) { create(:announcement, :published, client: client) }
+  let(:request) do
+    create(:request, provider: provider, client: client, announcement: announcement,
+           response_message: "I can help", proposed_amount_cents: 400_000)
+  end
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
+    context "with wrong provider" do
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
+      let(:request) do
+        create(:request, :accepted, provider: provider, client: client, announcement: announcement)
+      end
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, reason: "Changed mind").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot withdraw request in accepted state")
+      end
+    end
+  end
+end
```
