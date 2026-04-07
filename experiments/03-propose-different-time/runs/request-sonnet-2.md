# Experiment: 03-propose-different-time
# App: request | Model: sonnet | Run: 2
# Branch: experiment/03-propose-different-time/request/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**New state machine flow:**
- `created` → `counter_proposed` (provider calls `counter_propose` with `proposed_at`)
- `counter_proposed` → `accepted` (client calls `accept_counter`, `scheduled_at` is updated to the proposed time)
- `counter_proposed` → `declined` (client calls `decline_counter`)

**Changes:**
- Migration: `counter_proposed_at` column on requests
- `Request` model: new state, events, validation, and `counter_proposed` cancellable
- 3 services: `CounterProposeService`, `AcceptCounterService`, `DeclineCounterService`
- 3 API endpoints: `PATCH /api/requests/:id/counter_propose`, `accept_counter`, `decline_counter`
- Mailer methods + email templates for all 3 events (client notified on counter-proposal, provider notified on accept/decline)
- Factory trait `:counter_proposed` and full specs — 312 tests, 0 failures

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..dd6e563 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject, :counter_propose, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -118,6 +118,38 @@ def reject
       handle_service_result(result)
     end
 
+    def counter_propose
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Requests::CounterProposeService.new(
+        request: @the_request,
+        provider: provider,
+        proposed_at: params[:proposed_at]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptCounterService.new(request: @the_request, client: client).call
+      handle_service_result(result)
+    end
+
+    def decline_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineCounterService.new(request: @the_request, client: client).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -169,6 +201,7 @@ def request_detail_json(req)
         currency: req.currency,
         cancel_reason: req.cancel_reason,
         reject_reason: req.reject_reason,
+        counter_proposed_at: req.counter_proposed_at,
         started_at: req.started_at,
         completed_at: req.completed_at,
         client_id: req.client_id,
diff --git a/affordance_request/app/mailers/request_mailer.rb b/affordance_request/app/mailers/request_mailer.rb
index 51ef746..58441cc 100644
--- a/affordance_request/app/mailers/request_mailer.rb
+++ b/affordance_request/app/mailers/request_mailer.rb
@@ -47,6 +47,24 @@ def request_rejected(recipient, payload)
     mail(to: recipient.email, subject: "Request ##{@request_id} rejected")
   end
 
+  def request_counter_proposed(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Provider proposed a new time for request ##{@request_id}")
+  end
+
+  def request_counter_accepted(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Counter-proposal accepted for request ##{@request_id}")
+  end
+
+  def request_counter_declined(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Counter-proposal declined for request ##{@request_id}")
+  end
+
   def review_reminder(recipient, payload)
     @recipient = recipient
     @request_id = payload[:request_id]
diff --git a/affordance_request/app/models/request.rb b/affordance_request/app/models/request.rb
index 1c6cff4..60e9853 100644
--- a/affordance_request/app/models/request.rb
+++ b/affordance_request/app/models/request.rb
@@ -13,6 +13,7 @@ class Request < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :counter_proposed_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -37,6 +38,7 @@ class Request < ApplicationRecord
     state :missed
     state :canceled
     state :rejected
+    state :counter_proposed
 
     event :accept do
       transitions from: :created, to: :accepted
@@ -46,6 +48,18 @@ class Request < ApplicationRecord
       transitions from: :created, to: :declined
     end
 
+    event :counter_propose do
+      transitions from: :created, to: :counter_proposed
+    end
+
+    event :accept_counter do
+      transitions from: :counter_proposed, to: :accepted
+    end
+
+    event :decline_counter do
+      transitions from: :counter_proposed, to: :declined
+    end
+
     event :miss do
       transitions from: :created, to: :missed
     end
@@ -65,7 +79,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:created, :accepted, :created_accepted], to: :canceled
+      transitions from: [:created, :accepted, :created_accepted, :counter_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/affordance_request/app/services/requests/accept_counter_service.rb b/affordance_request/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..31fcb15
--- /dev/null
+++ b/affordance_request/app/services/requests/accept_counter_service.rb
@@ -0,0 +1,26 @@
+module Requests
+  class AcceptCounterService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.scheduled_at = @request.counter_proposed_at
+      @request.accept_counter!
+
+      NotificationService.notify(@request.provider, :request_counter_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter-proposal on request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/app/services/requests/counter_propose_service.rb b/affordance_request/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..951c0b1
--- /dev/null
+++ b/affordance_request/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,28 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_at:)
+      @request = request
+      @provider = provider
+      @proposed_at = proposed_at
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_at.blank?
+
+      @request.counter_proposed_at = @proposed_at
+      @request.counter_propose!
+
+      NotificationService.notify(@request.client, :request_counter_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot counter-propose on request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/app/services/requests/decline_counter_service.rb b/affordance_request/app/services/requests/decline_counter_service.rb
new file mode 100644
index 0000000..5921135
--- /dev/null
+++ b/affordance_request/app/services/requests/decline_counter_service.rb
@@ -0,0 +1,25 @@
+module Requests
+  class DeclineCounterService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.decline_counter!
+
+      NotificationService.notify(@request.provider, :request_counter_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline counter-proposal on request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/app/views/request_mailer/request_counter_accepted.text.erb b/affordance_request/app/views/request_mailer/request_counter_accepted.text.erb
new file mode 100644
index 0000000..96772da
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_counter_accepted.text.erb
@@ -0,0 +1,5 @@
+Hi <%= @recipient.name %>,
+
+The client has accepted your counter-proposal for request #<%= @request_id %>.
+
+The request is now accepted with the new proposed time.
diff --git a/affordance_request/app/views/request_mailer/request_counter_declined.text.erb b/affordance_request/app/views/request_mailer/request_counter_declined.text.erb
new file mode 100644
index 0000000..1b4769d
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_counter_declined.text.erb
@@ -0,0 +1,5 @@
+Hi <%= @recipient.name %>,
+
+The client has declined your counter-proposal for request #<%= @request_id %>.
+
+The request has been declined.
diff --git a/affordance_request/app/views/request_mailer/request_counter_proposed.text.erb b/affordance_request/app/views/request_mailer/request_counter_proposed.text.erb
new file mode 100644
index 0000000..937a451
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_counter_proposed.text.erb
@@ -0,0 +1,5 @@
+Hi <%= @recipient.name %>,
+
+The provider has proposed a new time for your request #<%= @request_id %>.
+
+Please log in to view the proposed time and either accept or decline the counter-proposal.
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..79ab046 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -21,6 +21,9 @@
         patch :fulfill
         patch :cancel
         patch :reject
+        patch :counter_propose
+        patch :accept_counter
+        patch :decline_counter
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request/db/migrate/20260407112641_add_counter_proposal_to_requests.rb b/affordance_request/db/migrate/20260407112641_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..37a18c9
--- /dev/null
+++ b/affordance_request/db/migrate/20260407112641_add_counter_proposal_to_requests.rb
@@ -0,0 +1,5 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :counter_proposed_at, :datetime
+  end
+end
diff --git a/affordance_request/db/schema.rb b/affordance_request/db/schema.rb
index 18c568a..1f394c7 100644
--- a/affordance_request/db/schema.rb
+++ b/affordance_request/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_112641) do
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
@@ -73,11 +95,15 @@
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
+    t.datetime "proposed_at"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
@@ -104,6 +130,8 @@
   end
 
   add_foreign_key "cards", "clients"
+  add_foreign_key "orders", "clients"
+  add_foreign_key "orders", "providers"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "requests"
   add_foreign_key "requests", "clients"
diff --git a/affordance_request/spec/factories/requests.rb b/affordance_request/spec/factories/requests.rb
index ba19812..c2137d1 100644
--- a/affordance_request/spec/factories/requests.rb
+++ b/affordance_request/spec/factories/requests.rb
@@ -32,6 +32,11 @@
       state { "declined" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      counter_proposed_at { 5.days.from_now }
+    end
+
     trait :missed do
       state { "missed" }
     end
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..cb78cb3 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -224,4 +224,71 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/requests/:id/counter_propose" do
+    let(:req) { create(:request, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "counter-proposes as provider with a new time" do
+      patch "/api/requests/#{req.id}/counter_propose", params: { proposed_at: proposed_time }, headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("counter_proposed")
+      expect(body["counter_proposed_at"]).to be_present
+    end
+
+    it "returns error without proposed_at" do
+      patch "/api/requests/#{req.id}/counter_propose", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{req.id}/counter_propose", params: { proposed_at: proposed_time }, headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_counter" do
+    let(:req) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+    it "accepts counter-proposal as client" do
+      patch "/api/requests/#{req.id}/accept_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("accepted")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{req.id}/accept_counter", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when request is not counter_proposed" do
+      created_req = create(:request, client: client, provider: provider)
+      patch "/api/requests/#{created_req.id}/accept_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_counter" do
+    let(:req) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+    it "declines counter-proposal as client" do
+      patch "/api/requests/#{req.id}/decline_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("declined")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{req.id}/decline_counter", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when request is not counter_proposed" do
+      created_req = create(:request, client: client, provider: provider)
+      patch "/api/requests/#{created_req.id}/decline_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
diff --git a/affordance_request/spec/services/requests/accept_counter_service_spec.rb b/affordance_request/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..2f491da
--- /dev/null
+++ b/affordance_request/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,38 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "transitions to accepted and updates scheduled_at" do
+      request = create(:request, :counter_proposed, client: client, provider: provider)
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("accepted")
+      expect(request.scheduled_at).to be_within(1.second).of(request.counter_proposed_at)
+    end
+
+    it "notifies the provider" do
+      request = create(:request, :counter_proposed, client: client, provider: provider)
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=request_counter_accepted")
+    end
+
+    it "fails for another client's request" do
+      request = create(:request, :counter_proposed, client: client, provider: provider)
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails when request is not in counter_proposed state" do
+      request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept counter-proposal")
+    end
+  end
+end
diff --git a/affordance_request/spec/services/requests/counter_propose_service_spec.rb b/affordance_request/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..059838e
--- /dev/null
+++ b/affordance_request/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,45 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "sets state to counter_proposed and stores proposed time" do
+      request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: request, provider: provider, proposed_at: proposed_time).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("counter_proposed")
+      expect(request.counter_proposed_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "notifies the client" do
+      request = create(:request, client: client, provider: provider)
+      described_class.new(request: request, provider: provider, proposed_at: proposed_time).call
+      expect(read_notification_log).to include("event=request_counter_proposed")
+    end
+
+    it "fails for another provider's request" do
+      request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: request, provider: other_provider, proposed_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails without a proposed time" do
+      request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: request, provider: provider, proposed_at: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails when request is already accepted" do
+      request = create(:request, :accepted, client: client, provider: provider)
+      result = described_class.new(request: request, provider: provider, proposed_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot counter-propose")
+    end
+  end
+end
diff --git a/affordance_request/spec/services/requests/decline_counter_service_spec.rb b/affordance_request/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..adb5602
--- /dev/null
+++ b/affordance_request/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,36 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+
+  describe "#call" do
+    it "transitions to declined" do
+      request = create(:request, :counter_proposed, client: client, provider: provider)
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("declined")
+    end
+
+    it "notifies the provider" do
+      request = create(:request, :counter_proposed, client: client, provider: provider)
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=request_counter_declined")
+    end
+
+    it "fails for another client's request" do
+      request = create(:request, :counter_proposed, client: client, provider: provider)
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails when request is not in counter_proposed state" do
+      request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline counter-proposal")
+    end
+  end
+end
```
