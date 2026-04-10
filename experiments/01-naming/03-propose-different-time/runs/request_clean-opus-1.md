# Experiment: 03-propose-different-time
# App: request_clean | Model: opus | Run: 1
# Branch: experiment/03-propose-different-time/request_clean/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**New state: `proposed`** — sits between `pending` and `confirmed` in the workflow.

**Three new transitions:**
- `propose_new_time` — provider proposes an alternative time (pending → proposed), stores `proposed_scheduled_at`
- `accept_proposal` — client accepts the counter-proposal (proposed → confirmed), moves `proposed_scheduled_at` into `scheduled_at`
- `decline_proposal` — client declines (proposed → pending), clears `proposed_scheduled_at`

**Files changed:**
- Migration adding `proposed_scheduled_at` column
- `Request` model — new AASM states and events
- 3 new service classes following existing patterns
- `RequestsController` — 3 new actions with auth checks
- Routes — 3 new member routes
- Tests — 15 new specs (model + request), all 280 tests passing

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..cd755a1 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_new_time, :accept_proposal, :decline_proposal]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,44 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_new_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_scheduled_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Requests::ProposeNewTimeService.new(
+        request: @request,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptProposalService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
+    def decline_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineProposalService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -139,6 +177,7 @@ def request_detail_json(request)
         notes: request.notes,
         amount_cents: request.amount_cents,
         currency: request.currency,
+        proposed_scheduled_at: request.proposed_scheduled_at,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
         started_at: request.started_at,
diff --git a/affordance_request_clean/app/models/request.rb b/affordance_request_clean/app/models/request.rb
index 67cb0ca..603a2cf 100644
--- a/affordance_request_clean/app/models/request.rb
+++ b/affordance_request_clean/app/models/request.rb
@@ -29,12 +29,31 @@ class Request < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :proposed
     state :confirmed
     state :in_progress
     state :completed
     state :canceled
     state :rejected
 
+    event :propose_new_time do
+      transitions from: :pending, to: :proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :proposed, to: :confirmed
+      after do
+        update!(scheduled_at: proposed_scheduled_at, proposed_scheduled_at: nil)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil)
+      end
+    end
+
     event :confirm do
       transitions from: :pending, to: :confirmed
     end
diff --git a/affordance_request_clean/app/services/requests/accept_proposal_service.rb b/affordance_request_clean/app/services/requests/accept_proposal_service.rb
new file mode 100644
index 0000000..00e5297
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/accept_proposal_service.rb
@@ -0,0 +1,24 @@
+module Requests
+  class AcceptProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.accept_proposal!
+      NotificationService.notify(@request.provider, :proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/decline_proposal_service.rb b/affordance_request_clean/app/services/requests/decline_proposal_service.rb
new file mode 100644
index 0000000..5258c23
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/decline_proposal_service.rb
@@ -0,0 +1,24 @@
+module Requests
+  class DeclineProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.decline_proposal!
+      NotificationService.notify(@request.provider, :proposal_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/propose_new_time_service.rb b/affordance_request_clean/app/services/requests/propose_new_time_service.rb
new file mode 100644
index 0000000..1c56b46
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/propose_new_time_service.rb
@@ -0,0 +1,27 @@
+module Requests
+  class ProposeNewTimeService
+    def initialize(request:, provider:, proposed_scheduled_at:)
+      @request = request
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @request.proposed_scheduled_at = @proposed_scheduled_at
+      @request.propose_new_time!
+      NotificationService.notify(@request.client, :new_time_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot propose new time for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..1d524c2 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -17,6 +17,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :propose_new_time
+        patch :accept_proposal
+        patch :decline_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request_clean/db/migrate/20260407213635_add_proposed_scheduled_at_to_requests.rb b/affordance_request_clean/db/migrate/20260407213635_add_proposed_scheduled_at_to_requests.rb
new file mode 100644
index 0000000..a95e8f4
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260407213635_add_proposed_scheduled_at_to_requests.rb
@@ -0,0 +1,5 @@
+class AddProposedScheduledAtToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..01beb65 100644
--- a/affordance_request_clean/db/schema.rb
+++ b/affordance_request_clean/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_213635) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -78,6 +78,7 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_request_clean/spec/factories/requests.rb b/affordance_request_clean/spec/factories/requests.rb
index c63766e..93adf2a 100644
--- a/affordance_request_clean/spec/factories/requests.rb
+++ b/affordance_request_clean/spec/factories/requests.rb
@@ -9,6 +9,11 @@
     amount_cents { 350_000 }
     currency { "RUB" }
 
+    trait :proposed do
+      state { "proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :confirmed do
       state { "confirmed" }
     end
diff --git a/affordance_request_clean/spec/models/request_spec.rb b/affordance_request_clean/spec/models/request_spec.rb
index 218bb0f..c0c7c59 100644
--- a/affordance_request_clean/spec/models/request_spec.rb
+++ b/affordance_request_clean/spec/models/request_spec.rb
@@ -55,6 +55,56 @@
       expect(request).to be_pending
     end
 
+    describe "propose_new_time event" do
+      it "transitions from pending to proposed" do
+        request.propose_new_time!
+        expect(request).to be_proposed
+      end
+
+      it "cannot propose from confirmed" do
+        request.confirm!
+        expect { request.propose_new_time! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_proposal event" do
+      before do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.propose_new_time!
+      end
+
+      it "transitions from proposed to confirmed" do
+        request.accept_proposal!
+        expect(request).to be_confirmed
+      end
+
+      it "updates scheduled_at to proposed time and clears proposed_scheduled_at" do
+        proposed_time = request.proposed_scheduled_at
+        request.accept_proposal!
+        request.reload
+        expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.proposed_scheduled_at).to be_nil
+      end
+    end
+
+    describe "decline_proposal event" do
+      before do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.propose_new_time!
+      end
+
+      it "transitions from proposed back to pending" do
+        request.decline_proposal!
+        expect(request).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        request.decline_proposal!
+        request.reload
+        expect(request.proposed_scheduled_at).to be_nil
+      end
+    end
+
     describe "confirm event" do
       it "transitions from pending to confirmed" do
         request.confirm!
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..13c6a85 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -166,6 +166,81 @@
     end
   end
 
+  describe "PATCH /api/requests/:id/propose_new_time" do
+    let(:request) { create(:request, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "proposes a new time as provider" do
+      patch "/api/requests/#{request.id}/propose_new_time",
+        params: { proposed_scheduled_at: proposed_time },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("proposed")
+      expect(body["proposed_scheduled_at"]).to be_present
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/requests/#{request.id}/propose_new_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{request.id}/propose_new_time",
+        params: { proposed_scheduled_at: proposed_time },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when wrong provider tries to propose" do
+      other_provider = create(:provider)
+      patch "/api/requests/#{request.id}/propose_new_time",
+        params: { proposed_scheduled_at: proposed_time },
+        headers: auth_headers(other_provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_proposal" do
+    let(:request) { create(:request, :proposed, client: client, provider: provider) }
+
+    it "accepts proposal as client" do
+      patch "/api/requests/#{request.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+      expect(body["proposed_scheduled_at"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/accept_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error for non-proposed request" do
+      pending_request = create(:request, client: client, provider: provider)
+      patch "/api/requests/#{pending_request.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_proposal" do
+    let(:request) { create(:request, :proposed, client: client, provider: provider) }
+
+    it "declines proposal as client" do
+      patch "/api/requests/#{request.id}/decline_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["proposed_scheduled_at"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/decline_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
   describe "PATCH /api/requests/:id/reject" do
     let(:request) { create(:request, :confirmed, client: client, provider: provider) }
 
```
