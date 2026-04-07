# Experiment: 03-propose-different-time
# App: request | Model: opus | Run: 3
# Branch: experiment/03-propose-different-time/request/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**New state**: `counter_proposed` — entered when a provider proposes a different time

**New flow**:
1. Provider calls `PATCH /api/requests/:id/propose_time` with `proposed_scheduled_at` → request moves from `created` to `counter_proposed`
2. Client calls `PATCH /api/requests/:id/accept_proposal` → request moves to `accepted` and `scheduled_at` is updated to the proposed time
3. Client calls `PATCH /api/requests/:id/decline_proposal` → request moves to `declined`

Clients can also still `cancel` a counter-proposed request.

**Files changed**:
- Migration adding `proposed_scheduled_at` column
- Model: 3 new AASM events, new state, cancel also allowed from `counter_proposed`
- 3 new services: `ProposeTimeService`, `AcceptProposalService`, `DeclineProposalService`
- Controller: 3 new actions with auth checks
- Routes: 3 new member routes
- Mailer: 3 new notification methods
- Full test coverage (317 tests, 0 failures)

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..a51f6fc 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :propose_time, :accept_proposal, :decline_proposal, :start, :fulfill, :cancel, :reject]
 
     def index
       requests = scoped_requests
@@ -70,6 +70,38 @@ def decline
       handle_service_result(result)
     end
 
+    def propose_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_scheduled_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Requests::ProposeTimeService.new(
+        request: @the_request,
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
+      result = Requests::AcceptProposalService.new(request: @the_request, client: client).call
+      handle_service_result(result)
+    end
+
+    def decline_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineProposalService.new(request: @the_request, client: client).call
+      handle_service_result(result)
+    end
+
     def start
       provider = current_provider!
       return if performed?
@@ -169,6 +201,7 @@ def request_detail_json(req)
         currency: req.currency,
         cancel_reason: req.cancel_reason,
         reject_reason: req.reject_reason,
+        proposed_scheduled_at: req.proposed_scheduled_at,
         started_at: req.started_at,
         completed_at: req.completed_at,
         client_id: req.client_id,
diff --git a/affordance_request/app/mailers/request_mailer.rb b/affordance_request/app/mailers/request_mailer.rb
index 51ef746..88afe0f 100644
--- a/affordance_request/app/mailers/request_mailer.rb
+++ b/affordance_request/app/mailers/request_mailer.rb
@@ -23,6 +23,24 @@ def request_declined(recipient, payload)
     mail(to: recipient.email, subject: "Request ##{@request_id} declined")
   end
 
+  def request_time_proposed(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - new time proposed")
+  end
+
+  def request_proposal_accepted(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - proposed time accepted")
+  end
+
+  def request_proposal_declined(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - proposed time declined")
+  end
+
   def request_started(recipient, payload)
     @recipient = recipient
     @request_id = payload[:request_id]
diff --git a/affordance_request/app/models/request.rb b/affordance_request/app/models/request.rb
index 1c6cff4..56d56f8 100644
--- a/affordance_request/app/models/request.rb
+++ b/affordance_request/app/models/request.rb
@@ -31,6 +31,7 @@ class Request < ApplicationRecord
     state :created, initial: true
     state :created_accepted
     state :accepted
+    state :counter_proposed
     state :started
     state :fulfilled
     state :declined
@@ -42,6 +43,21 @@ class Request < ApplicationRecord
       transitions from: :created, to: :accepted
     end
 
+    event :propose_different_time do
+      transitions from: :created, to: :counter_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(scheduled_at: proposed_scheduled_at, proposed_scheduled_at: nil)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :counter_proposed, to: :declined
+    end
+
     event :decline do
       transitions from: :created, to: :declined
     end
@@ -65,7 +81,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:created, :accepted, :created_accepted], to: :canceled
+      transitions from: [:created, :accepted, :created_accepted, :counter_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/affordance_request/app/services/requests/accept_proposal_service.rb b/affordance_request/app/services/requests/accept_proposal_service.rb
new file mode 100644
index 0000000..5dbf4f7
--- /dev/null
+++ b/affordance_request/app/services/requests/accept_proposal_service.rb
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
+      NotificationService.notify(@request.provider, :request_proposal_accepted, request_id: @request.id)
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
diff --git a/affordance_request/app/services/requests/decline_proposal_service.rb b/affordance_request/app/services/requests/decline_proposal_service.rb
new file mode 100644
index 0000000..e239db8
--- /dev/null
+++ b/affordance_request/app/services/requests/decline_proposal_service.rb
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
+      NotificationService.notify(@request.provider, :request_proposal_declined, request_id: @request.id)
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
diff --git a/affordance_request/app/services/requests/propose_time_service.rb b/affordance_request/app/services/requests/propose_time_service.rb
new file mode 100644
index 0000000..7ff3771
--- /dev/null
+++ b/affordance_request/app/services/requests/propose_time_service.rb
@@ -0,0 +1,26 @@
+module Requests
+  class ProposeTimeService
+    def initialize(request:, provider:, proposed_scheduled_at:)
+      @request = request
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+
+      @request.update!(proposed_scheduled_at: @proposed_scheduled_at)
+      @request.propose_different_time!
+      NotificationService.notify(@request.client, :request_time_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot propose a different time for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..2e93a3b 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -17,6 +17,9 @@
       member do
         patch :accept
         patch :decline
+        patch :propose_time
+        patch :accept_proposal
+        patch :decline_proposal
         patch :start
         patch :fulfill
         patch :cancel
diff --git a/affordance_request/db/migrate/20260407104538_add_proposed_scheduled_at_to_requests.rb b/affordance_request/db/migrate/20260407104538_add_proposed_scheduled_at_to_requests.rb
new file mode 100644
index 0000000..a95e8f4
--- /dev/null
+++ b/affordance_request/db/migrate/20260407104538_add_proposed_scheduled_at_to_requests.rb
@@ -0,0 +1,5 @@
+class AddProposedScheduledAtToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+  end
+end
diff --git a/affordance_request/db/schema.rb b/affordance_request/db/schema.rb
index 18c568a..9d9105d 100644
--- a/affordance_request/db/schema.rb
+++ b/affordance_request/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_104538) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -36,6 +36,28 @@
     t.index ["email"], name: "index_clients_on_email", unique: true
   end
 
+  create_table "orders", force: :cascade do |t|
+    t.integer "amount_cents", null: false
+    t.text "cancel_reason"
+    t.integer "client_id", null: false
+    t.datetime "completed_at"
+    t.datetime "created_at", null: false
+    t.string "currency", default: "RUB", null: false
+    t.integer "duration_minutes", null: false
+    t.string "location"
+    t.text "notes"
+    t.integer "provider_id", null: false
+    t.text "reject_reason"
+    t.datetime "scheduled_at", null: false
+    t.datetime "started_at"
+    t.string "state", default: "pending", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_orders_on_client_id"
+    t.index ["provider_id"], name: "index_orders_on_provider_id"
+    t.index ["scheduled_at"], name: "index_orders_on_scheduled_at"
+    t.index ["state"], name: "index_orders_on_state"
+  end
+
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
     t.integer "card_id"
@@ -78,6 +100,7 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
@@ -104,6 +127,8 @@
   end
 
   add_foreign_key "cards", "clients"
+  add_foreign_key "orders", "clients"
+  add_foreign_key "orders", "providers"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "requests"
   add_foreign_key "requests", "clients"
diff --git a/affordance_request/spec/factories/requests.rb b/affordance_request/spec/factories/requests.rb
index ba19812..5e9ac7e 100644
--- a/affordance_request/spec/factories/requests.rb
+++ b/affordance_request/spec/factories/requests.rb
@@ -28,6 +28,11 @@
       completed_at { Time.current }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :declined do
       state { "declined" }
     end
diff --git a/affordance_request/spec/models/request_spec.rb b/affordance_request/spec/models/request_spec.rb
index c3d38c1..22a74a1 100644
--- a/affordance_request/spec/models/request_spec.rb
+++ b/affordance_request/spec/models/request_spec.rb
@@ -67,6 +67,52 @@
       end
     end
 
+    describe "propose_different_time event" do
+      it "transitions from created to counter_proposed" do
+        req.propose_different_time!
+        expect(req).to be_counter_proposed
+      end
+
+      it "cannot propose from accepted" do
+        req.accept!
+        expect { req.propose_different_time! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_proposal event" do
+      let(:cp_req) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to accepted" do
+        cp_req.accept_proposal!
+        expect(cp_req).to be_accepted
+      end
+
+      it "updates scheduled_at to proposed time and clears proposed_scheduled_at" do
+        proposed = cp_req.proposed_scheduled_at
+        cp_req.accept_proposal!
+        cp_req.reload
+        expect(cp_req.scheduled_at).to be_within(1.second).of(proposed)
+        expect(cp_req.proposed_scheduled_at).to be_nil
+      end
+
+      it "cannot accept proposal from created" do
+        expect { req.accept_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_proposal event" do
+      let(:cp_req) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to declined" do
+        cp_req.decline_proposal!
+        expect(cp_req).to be_declined
+      end
+
+      it "cannot decline proposal from created" do
+        expect { req.decline_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
     describe "decline event" do
       it "transitions from created to declined" do
         req.decline!
@@ -150,6 +196,13 @@
         expect(ca_req).to be_canceled
       end
 
+      it "transitions from counter_proposed to canceled" do
+        cp_req = create(:request, :counter_proposed)
+        cp_req.update!(cancel_reason: "Changed my mind")
+        cp_req.cancel!
+        expect(cp_req).to be_canceled
+      end
+
       it "cannot cancel from started" do
         req.accept!
         req.start!
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..d7764d9 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -158,6 +158,59 @@
     end
   end
 
+  describe "PATCH /api/requests/:id/propose_time" do
+    let(:req) { create(:request, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "proposes a different time as provider" do
+      patch "/api/requests/#{req.id}/propose_time", params: { proposed_scheduled_at: proposed_time }, headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("counter_proposed")
+      expect(body["proposed_scheduled_at"]).to be_present
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/requests/#{req.id}/propose_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{req.id}/propose_time", params: { proposed_scheduled_at: proposed_time }, headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_proposal" do
+    let(:req) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+    it "accepts the proposed time as client" do
+      patch "/api/requests/#{req.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["state"]).to eq("accepted")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{req.id}/accept_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_proposal" do
+    let(:req) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+    it "declines the proposed time as client" do
+      patch "/api/requests/#{req.id}/decline_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["state"]).to eq("declined")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{req.id}/decline_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
   describe "PATCH /api/requests/:id/start" do
     let(:req) { create(:request, :accepted, client: client, provider: provider) }
 
diff --git a/affordance_request/spec/services/requests/accept_proposal_service_spec.rb b/affordance_request/spec/services/requests/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..f0e7ecc
--- /dev/null
+++ b/affordance_request/spec/services/requests/accept_proposal_service_spec.rb
@@ -0,0 +1,37 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:req) { create(:request, :counter_proposed, client: client, provider: provider, proposed_scheduled_at: proposed_time) }
+
+  describe "#call" do
+    it "accepts the proposed time" do
+      result = described_class.new(request: req, client: client).call
+      expect(result[:success]).to be true
+      expect(req.reload.state).to eq("accepted")
+      expect(req.scheduled_at).to be_within(1.second).of(proposed_time)
+      expect(req.proposed_scheduled_at).to be_nil
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: req, client: client).call
+      expect(read_notification_log).to include("event=request_proposal_accepted")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: req, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-counter_proposed request" do
+      created_req = create(:request, client: client, provider: provider)
+      result = described_class.new(request: created_req, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept proposal")
+    end
+  end
+end
diff --git a/affordance_request/spec/services/requests/decline_proposal_service_spec.rb b/affordance_request/spec/services/requests/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..4c6998f
--- /dev/null
+++ b/affordance_request/spec/services/requests/decline_proposal_service_spec.rb
@@ -0,0 +1,34 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:req) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    it "declines the proposed time" do
+      result = described_class.new(request: req, client: client).call
+      expect(result[:success]).to be true
+      expect(req.reload.state).to eq("declined")
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: req, client: client).call
+      expect(read_notification_log).to include("event=request_proposal_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: req, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-counter_proposed request" do
+      created_req = create(:request, client: client, provider: provider)
+      result = described_class.new(request: created_req, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline proposal")
+    end
+  end
+end
diff --git a/affordance_request/spec/services/requests/propose_time_service_spec.rb b/affordance_request/spec/services/requests/propose_time_service_spec.rb
new file mode 100644
index 0000000..545959c
--- /dev/null
+++ b/affordance_request/spec/services/requests/propose_time_service_spec.rb
@@ -0,0 +1,36 @@
+require "rails_helper"
+
+RSpec.describe Requests::ProposeTimeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:req) { create(:request, client: client, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "proposes a different time for a created request" do
+      result = described_class.new(request: req, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be true
+      expect(req.reload.state).to eq("counter_proposed")
+      expect(req.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "notifies the client" do
+      described_class.new(request: req, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(read_notification_log).to include("event=request_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(request: req, provider: other_provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-created request" do
+      req.update!(state: "accepted")
+      result = described_class.new(request: req, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose a different time")
+    end
+  end
+end
```
