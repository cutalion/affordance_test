# Experiment: e06-withdraw-response
# App: app_delta | Model: opus | Run: 1
# Branch: debt_experiment/e06-withdraw-response/app_delta/opus/run-1

---

## Claude Output

All 181 tests pass. Here's what was implemented:

**Model** (`app/models/response.rb`): Added `withdrawn` state and `withdraw` event, allowing transition from `pending` to `withdrawn`.

**Service** (`app/services/responses/withdraw_service.rb`): New `WithdrawService` that verifies the provider owns the response, transitions it to `withdrawn`, and notifies the client.

**Controller** (`app/controllers/api/responses_controller.rb`): Added `withdraw` action requiring provider authentication, delegating to the service.

**Route** (`config/routes.rb`): Added `PATCH /api/responses/:id/withdraw`.

**Tests**: Model specs for the withdraw state transition (3 cases), service specs covering success, wrong provider, already selected, and already rejected scenarios (4 cases).

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/responses_controller.rb b/app_delta/app/controllers/api/responses_controller.rb
index a000e65..d966d3d 100644
--- a/app_delta/app/controllers/api/responses_controller.rb
+++ b/app_delta/app/controllers/api/responses_controller.rb
@@ -1,7 +1,7 @@
 module Api
   class ResponsesController < BaseController
     before_action :set_announcement, only: [:index, :create]
-    before_action :set_response, only: [:select, :reject]
+    before_action :set_response, only: [:select, :reject, :withdraw]
 
     def index
       responses = @announcement.responses
@@ -46,6 +46,14 @@ def reject
       handle_service_result(result)
     end
 
+    def withdraw
+      provider = current_provider!
+      return if performed?
+
+      result = Responses::WithdrawService.new(response: @response, provider: provider).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_announcement
diff --git a/app_delta/app/models/response.rb b/app_delta/app/models/response.rb
index 1c2aad5..2bdceb1 100644
--- a/app_delta/app/models/response.rb
+++ b/app_delta/app/models/response.rb
@@ -10,6 +10,7 @@ class Response < ApplicationRecord
     state :pending, initial: true
     state :selected
     state :rejected
+    state :withdrawn
 
     event :select do
       transitions from: :pending, to: :selected
@@ -18,5 +19,9 @@ class Response < ApplicationRecord
     event :reject do
       transitions from: :pending, to: :rejected
     end
+
+    event :withdraw do
+      transitions from: :pending, to: :withdrawn
+    end
   end
 end
diff --git a/app_delta/app/services/responses/withdraw_service.rb b/app_delta/app/services/responses/withdraw_service.rb
new file mode 100644
index 0000000..99fe20c
--- /dev/null
+++ b/app_delta/app/services/responses/withdraw_service.rb
@@ -0,0 +1,24 @@
+module Responses
+  class WithdrawService
+    def initialize(response:, provider:)
+      @response = response
+      @provider = provider
+    end
+
+    def call
+      return error("Not your response") unless @response.provider_id == @provider.id
+
+      @response.withdraw!
+      NotificationService.notify(@response.announcement.client, :response_withdrawn, announcement_id: @response.announcement_id)
+      { success: true, response: @response }
+    rescue AASM::InvalidTransition
+      error("Cannot withdraw response in #{@response.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_delta/config/routes.rb b/app_delta/config/routes.rb
index d9e099b..8cdab39 100644
--- a/app_delta/config/routes.rb
+++ b/app_delta/config/routes.rb
@@ -42,6 +42,7 @@
       member do
         patch :select
         patch :reject
+        patch :withdraw
       end
     end
   end
diff --git a/app_delta/spec/factories/responses.rb b/app_delta/spec/factories/responses.rb
index 056f707..82ecd54 100644
--- a/app_delta/spec/factories/responses.rb
+++ b/app_delta/spec/factories/responses.rb
@@ -12,5 +12,9 @@
     trait :rejected do
       state { "rejected" }
     end
+
+    trait :withdrawn do
+      state { "withdrawn" }
+    end
   end
 end
diff --git a/app_delta/spec/models/response_spec.rb b/app_delta/spec/models/response_spec.rb
index 43a940a..c296ad7 100644
--- a/app_delta/spec/models/response_spec.rb
+++ b/app_delta/spec/models/response_spec.rb
@@ -51,5 +51,22 @@
         expect { response.reject! }.to raise_error(AASM::InvalidTransition)
       end
     end
+
+    describe "withdraw event" do
+      it "transitions from pending to withdrawn" do
+        response.withdraw!
+        expect(response).to be_withdrawn
+      end
+
+      it "cannot withdraw from selected state" do
+        response.select!
+        expect { response.withdraw! }.to raise_error(AASM::InvalidTransition)
+      end
+
+      it "cannot withdraw from rejected state" do
+        response.reject!
+        expect { response.withdraw! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
   end
 end
diff --git a/app_delta/spec/services/responses/withdraw_service_spec.rb b/app_delta/spec/services/responses/withdraw_service_spec.rb
new file mode 100644
index 0000000..af3c14a
--- /dev/null
+++ b/app_delta/spec/services/responses/withdraw_service_spec.rb
@@ -0,0 +1,52 @@
+require "rails_helper"
+
+RSpec.describe Responses::WithdrawService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:announcement) { create(:announcement, :published, client: client) }
+  let(:response) { create(:response, announcement: announcement, provider: provider) }
+
+  subject(:result) { described_class.new(response: response, provider: provider).call }
+
+  describe "#call" do
+    context "with valid withdrawal" do
+      it "withdraws the response" do
+        expect(result[:success]).to be true
+        expect(result[:response]).to be_withdrawn
+      end
+
+      it "notifies the client" do
+        result
+        expect(read_notification_log).to include("event=response_withdrawn")
+      end
+    end
+
+    context "when provider does not own the response" do
+      let(:other_provider) { create(:provider) }
+      subject(:result) { described_class.new(response: response, provider: other_provider).call }
+
+      it "returns error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Not your response")
+      end
+    end
+
+    context "when response is already selected" do
+      before { response.select! }
+
+      it "returns error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot withdraw")
+      end
+    end
+
+    context "when response is already rejected" do
+      before { response.reject! }
+
+      it "returns error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot withdraw")
+      end
+    end
+  end
+end
```
