# Experiment: 03-propose-different-time
# App: request | Model: sonnet | Run: 3
# Branch: experiment/03-propose-different-time/request/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**New state: `proposed`** — sits between `created` and `accepted`/`declined`

**3 new endpoints:**
- `PATCH /api/requests/:id/propose_time` (provider) — proposes alternative `scheduled_at` with optional reason; request enters `proposed` state, client is notified
- `PATCH /api/requests/:id/accept_proposal` (client) — accepts the counter-proposal; `scheduled_at` is updated to `proposed_at`, request becomes `accepted`, provider is notified
- `PATCH /api/requests/:id/decline_proposal` (client) — declines the counter-proposal; request becomes `declined`, provider is notified

**Files added/changed:** migration, model (new state + transitions), 3 services, controller, routes, mailer (3 new methods), 3 email templates, factory trait, 3 service specs, updated API request spec. All 314 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..8f32113 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject, :propose_time, :accept_proposal, :decline_proposal]
 
     def index
       requests = scoped_requests
@@ -118,6 +118,39 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_at].blank?
+        return render_unprocessable(["proposed_at is required"])
+      end
+
+      result = Requests::ProposeTimeService.new(
+        request: @the_request,
+        provider: provider,
+        proposed_at: params[:proposed_at],
+        propose_reason: params[:propose_reason]
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
     private
 
     def set_request
@@ -169,6 +202,8 @@ def request_detail_json(req)
         currency: req.currency,
         cancel_reason: req.cancel_reason,
         reject_reason: req.reject_reason,
+        proposed_at: req.proposed_at,
+        propose_reason: req.propose_reason,
         started_at: req.started_at,
         completed_at: req.completed_at,
         client_id: req.client_id,
diff --git a/affordance_request/app/mailers/request_mailer.rb b/affordance_request/app/mailers/request_mailer.rb
index 51ef746..7607061 100644
--- a/affordance_request/app/mailers/request_mailer.rb
+++ b/affordance_request/app/mailers/request_mailer.rb
@@ -47,6 +47,24 @@ def request_rejected(recipient, payload)
     mail(to: recipient.email, subject: "Request ##{@request_id} rejected")
   end
 
+  def request_time_proposed(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - provider proposed a different time")
+  end
+
+  def request_proposal_accepted(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - counter-proposal accepted")
+  end
+
+  def request_proposal_declined(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - counter-proposal declined")
+  end
+
   def review_reminder(recipient, payload)
     @recipient = recipient
     @request_id = payload[:request_id]
diff --git a/affordance_request/app/models/request.rb b/affordance_request/app/models/request.rb
index 1c6cff4..e4920d9 100644
--- a/affordance_request/app/models/request.rb
+++ b/affordance_request/app/models/request.rb
@@ -31,6 +31,7 @@ class Request < ApplicationRecord
     state :created, initial: true
     state :created_accepted
     state :accepted
+    state :proposed
     state :started
     state :fulfilled
     state :declined
@@ -43,7 +44,18 @@ class Request < ApplicationRecord
     end
 
     event :decline do
-      transitions from: :created, to: :declined
+      transitions from: [:created, :proposed], to: :declined
+    end
+
+    event :propose_time do
+      transitions from: :created, to: :proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :proposed, to: :accepted
+      after do
+        update!(scheduled_at: proposed_at)
+      end
     end
 
     event :miss do
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
index 0000000..7350685
--- /dev/null
+++ b/affordance_request/app/services/requests/decline_proposal_service.rb
@@ -0,0 +1,25 @@
+module Requests
+  class DeclineProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("Cannot decline proposal for request in #{@request.state} state") unless @request.proposed?
+
+      @request.decline!
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
index 0000000..5854e60
--- /dev/null
+++ b/affordance_request/app/services/requests/propose_time_service.rb
@@ -0,0 +1,29 @@
+module Requests
+  class ProposeTimeService
+    def initialize(request:, provider:, proposed_at:, propose_reason: nil)
+      @request = request
+      @provider = provider
+      @proposed_at = proposed_at
+      @propose_reason = propose_reason
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("proposed_at is required") if @proposed_at.blank?
+
+      @request.proposed_at = @proposed_at
+      @request.propose_reason = @propose_reason
+      @request.propose_time!
+      NotificationService.notify(@request.client, :request_time_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot propose time for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/app/views/request_mailer/request_proposal_accepted.text.erb b/affordance_request/app/views/request_mailer/request_proposal_accepted.text.erb
new file mode 100644
index 0000000..6856d65
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_proposal_accepted.text.erb
@@ -0,0 +1,4 @@
+Hello <%= @recipient.name %>,
+
+The client has accepted your proposed time for request #<%= @request_id %>.
+The appointment is now confirmed at the new time.
diff --git a/affordance_request/app/views/request_mailer/request_proposal_declined.text.erb b/affordance_request/app/views/request_mailer/request_proposal_declined.text.erb
new file mode 100644
index 0000000..a388eb9
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_proposal_declined.text.erb
@@ -0,0 +1,4 @@
+Hello <%= @recipient.name %>,
+
+The client has declined your proposed time for request #<%= @request_id %>.
+The request has been closed.
diff --git a/affordance_request/app/views/request_mailer/request_time_proposed.text.erb b/affordance_request/app/views/request_mailer/request_time_proposed.text.erb
new file mode 100644
index 0000000..cb4b260
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_time_proposed.text.erb
@@ -0,0 +1,4 @@
+Hello <%= @recipient.name %>,
+
+The provider has proposed a different time for request #<%= @request_id %>.
+Please review the proposal and accept or decline it.
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..e18dd87 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -21,6 +21,9 @@
         patch :fulfill
         patch :cancel
         patch :reject
+        patch :propose_time
+        patch :accept_proposal
+        patch :decline_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request/db/migrate/20260407113051_add_proposed_fields_to_requests.rb b/affordance_request/db/migrate/20260407113051_add_proposed_fields_to_requests.rb
new file mode 100644
index 0000000..c2732c5
--- /dev/null
+++ b/affordance_request/db/migrate/20260407113051_add_proposed_fields_to_requests.rb
@@ -0,0 +1,6 @@
+class AddProposedFieldsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_at, :datetime unless column_exists?(:requests, :proposed_at)
+    add_column :requests, :propose_reason, :text unless column_exists?(:requests, :propose_reason)
+  end
+end
diff --git a/affordance_request/db/schema.rb b/affordance_request/db/schema.rb
index 18c568a..c0fefce 100644
--- a/affordance_request/db/schema.rb
+++ b/affordance_request/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_113051) do
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
@@ -73,11 +95,16 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.string "counter_proposal_note"
+    t.datetime "counter_proposed_at"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.text "propose_reason"
+    t.datetime "proposed_at"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
@@ -104,6 +131,8 @@
   end
 
   add_foreign_key "cards", "clients"
+  add_foreign_key "orders", "clients"
+  add_foreign_key "orders", "providers"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "requests"
   add_foreign_key "requests", "clients"
diff --git a/affordance_request/spec/factories/requests.rb b/affordance_request/spec/factories/requests.rb
index ba19812..3322624 100644
--- a/affordance_request/spec/factories/requests.rb
+++ b/affordance_request/spec/factories/requests.rb
@@ -28,6 +28,12 @@
       completed_at { Time.current }
     end
 
+    trait :proposed do
+      state { "proposed" }
+      proposed_at { 4.days.from_now }
+      propose_reason { "I am busy at the original time" }
+    end
+
     trait :declined do
       state { "declined" }
     end
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..c4fff9c 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -224,4 +224,70 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/requests/:id/propose_time" do
+    let(:req) { create(:request, client: client, provider: provider) }
+    let(:new_time) { 5.days.from_now.iso8601 }
+
+    it "allows provider to propose a different time" do
+      patch "/api/requests/#{req.id}/propose_time",
+        params: { proposed_at: new_time, propose_reason: "I am busy" },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("proposed")
+      expect(body["proposed_at"]).to be_present
+      expect(body["propose_reason"]).to eq("I am busy")
+    end
+
+    it "returns error without proposed_at" do
+      patch "/api/requests/#{req.id}/propose_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{req.id}/propose_time",
+        params: { proposed_at: new_time },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_proposal" do
+    let(:req) { create(:request, :proposed, client: client, provider: provider, proposed_at: 5.days.from_now) }
+
+    it "allows client to accept counter-proposal" do
+      patch "/api/requests/#{req.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("accepted")
+    end
+
+    it "updates scheduled_at to proposed_at" do
+      original_proposed = req.proposed_at
+      patch "/api/requests/#{req.id}/accept_proposal", headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      expect(Time.parse(body["scheduled_at"])).to be_within(1.second).of(original_proposed)
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{req.id}/accept_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_proposal" do
+    let(:req) { create(:request, :proposed, client: client, provider: provider) }
+
+    it "allows client to decline counter-proposal" do
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
 end
diff --git a/affordance_request/spec/services/requests/accept_proposal_service_spec.rb b/affordance_request/spec/services/requests/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..e5248f3
--- /dev/null
+++ b/affordance_request/spec/services/requests/accept_proposal_service_spec.rb
@@ -0,0 +1,40 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:req) { create(:request, :proposed, client: client, provider: provider, proposed_at: proposed_time) }
+
+  describe "#call" do
+    it "transitions request to accepted state" do
+      result = described_class.new(request: req, client: client).call
+      expect(result[:success]).to be true
+      expect(req.reload.state).to eq("accepted")
+    end
+
+    it "updates scheduled_at to proposed_at" do
+      described_class.new(request: req, client: client).call
+      expect(req.reload.scheduled_at).to be_within(1.second).of(proposed_time)
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
+    it "fails for non-proposed request" do
+      req.update!(state: "created")
+      result = described_class.new(request: req, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept proposal")
+    end
+  end
+end
diff --git a/affordance_request/spec/services/requests/decline_proposal_service_spec.rb b/affordance_request/spec/services/requests/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..3f98200
--- /dev/null
+++ b/affordance_request/spec/services/requests/decline_proposal_service_spec.rb
@@ -0,0 +1,34 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:req) { create(:request, :proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    it "transitions request to declined state" do
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
+    it "fails for non-proposed request" do
+      req.update!(state: "created")
+      result = described_class.new(request: req, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline proposal")
+    end
+  end
+end
diff --git a/affordance_request/spec/services/requests/propose_time_service_spec.rb b/affordance_request/spec/services/requests/propose_time_service_spec.rb
new file mode 100644
index 0000000..13d2daa
--- /dev/null
+++ b/affordance_request/spec/services/requests/propose_time_service_spec.rb
@@ -0,0 +1,51 @@
+require "rails_helper"
+
+RSpec.describe Requests::ProposeTimeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:req) { create(:request, client: client, provider: provider) }
+  let(:new_time) { 5.days.from_now.iso8601 }
+
+  describe "#call" do
+    it "transitions request to proposed state" do
+      result = described_class.new(request: req, provider: provider, proposed_at: new_time).call
+      expect(result[:success]).to be true
+      expect(req.reload.state).to eq("proposed")
+    end
+
+    it "stores the proposed time" do
+      described_class.new(request: req, provider: provider, proposed_at: new_time).call
+      expect(req.reload.proposed_at).to be_within(1.second).of(Time.parse(new_time))
+    end
+
+    it "stores the optional reason" do
+      described_class.new(request: req, provider: provider, proposed_at: new_time, propose_reason: "busy").call
+      expect(req.reload.propose_reason).to eq("busy")
+    end
+
+    it "notifies the client" do
+      described_class.new(request: req, provider: provider, proposed_at: new_time).call
+      expect(read_notification_log).to include("event=request_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(request: req, provider: other_provider, proposed_at: new_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails when proposed_at is blank" do
+      result = described_class.new(request: req, provider: provider, proposed_at: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("proposed_at is required")
+    end
+
+    it "fails for non-created request" do
+      req.update!(state: "accepted")
+      result = described_class.new(request: req, provider: provider, proposed_at: new_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose time")
+    end
+  end
+end
```
