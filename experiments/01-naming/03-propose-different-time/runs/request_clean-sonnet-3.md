# Experiment: 03-propose-different-time
# App: request_clean | Model: sonnet | Run: 3
# Branch: experiment/03-propose-different-time/request_clean/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**New state:** `counter_proposed` (between `pending` and `confirmed`)

**New endpoints:**
- `PATCH /api/requests/:id/counter_propose` — provider proposes a new time (`proposed_scheduled_at` param required)
- `PATCH /api/requests/:id/accept_counter` — client accepts; `scheduled_at` is updated to the proposed time and request is confirmed
- `PATCH /api/requests/:id/decline_counter` — client declines; request is canceled

**New services:** `CounterProposeService`, `AcceptCounterService`, `DeclineCounterService`

**Notifications:** client is notified on counter-proposal; provider is notified on accept/decline

**JSON:** `counter_proposed_scheduled_at` is included in the request detail response

All 286 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..683f42e 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :counter_propose, :accept_counter, :decline_counter, :start, :complete, :cancel, :reject]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,38 @@ def reject
       handle_service_result(result)
     end
 
+    def counter_propose
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_scheduled_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Requests::CounterProposeService.new(
+        request: @request,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptCounterService.new(request: @request, client: client).call
+      handle_service_result(result)
+    end
+
+    def decline_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineCounterService.new(request: @request, client: client).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -141,6 +173,7 @@ def request_detail_json(request)
         currency: request.currency,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        counter_proposed_scheduled_at: request.counter_proposed_scheduled_at,
         started_at: request.started_at,
         completed_at: request.completed_at,
         client_id: request.client_id,
diff --git a/affordance_request_clean/app/mailers/request_mailer.rb b/affordance_request_clean/app/mailers/request_mailer.rb
index f10345b..c443b68 100644
--- a/affordance_request_clean/app/mailers/request_mailer.rb
+++ b/affordance_request_clean/app/mailers/request_mailer.rb
@@ -35,6 +35,24 @@ def request_rejected(recipient, payload)
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
+    mail(to: recipient.email, subject: "Client accepted your proposed time for request ##{@request_id}")
+  end
+
+  def request_counter_declined(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Client declined your proposed time for request ##{@request_id}")
+  end
+
   def review_reminder(recipient, payload)
     @recipient = recipient
     @request_id = payload[:request_id]
diff --git a/affordance_request_clean/app/models/request.rb b/affordance_request_clean/app/models/request.rb
index 67cb0ca..49debc8 100644
--- a/affordance_request_clean/app/models/request.rb
+++ b/affordance_request_clean/app/models/request.rb
@@ -13,6 +13,7 @@ class Request < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :counter_proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -29,6 +30,7 @@ class Request < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :counter_proposed
     state :confirmed
     state :in_progress
     state :completed
@@ -39,6 +41,21 @@ class Request < ApplicationRecord
       transitions from: :pending, to: :confirmed
     end
 
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_counter do
+      transitions from: :counter_proposed, to: :confirmed
+      after do
+        update!(scheduled_at: counter_proposed_scheduled_at)
+      end
+    end
+
+    event :decline_counter do
+      transitions from: :counter_proposed, to: :canceled
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
diff --git a/affordance_request_clean/app/services/requests/accept_counter_service.rb b/affordance_request_clean/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..f81486b
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/accept_counter_service.rb
@@ -0,0 +1,25 @@
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
diff --git a/affordance_request_clean/app/services/requests/counter_propose_service.rb b/affordance_request_clean/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..85983aa
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,28 @@
+module Requests
+  class CounterProposeService
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
+      @request.counter_proposed_scheduled_at = @proposed_scheduled_at
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
diff --git a/affordance_request_clean/app/services/requests/decline_counter_service.rb b/affordance_request_clean/app/services/requests/decline_counter_service.rb
new file mode 100644
index 0000000..0e0775c
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/decline_counter_service.rb
@@ -0,0 +1,26 @@
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
+      @request.cancel_reason = "Counter-proposal declined"
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
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..16ea4b7 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -13,6 +13,9 @@
     resources :requests, only: [:index, :show, :create] do
       member do
         patch :confirm
+        patch :counter_propose
+        patch :accept_counter
+        patch :decline_counter
         patch :start
         patch :complete
         patch :cancel
diff --git a/affordance_request_clean/db/migrate/20260407213252_add_counter_proposal_to_requests.rb b/affordance_request_clean/db/migrate/20260407213252_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..ff19df4
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260407213252_add_counter_proposal_to_requests.rb
@@ -0,0 +1,5 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :counter_proposed_scheduled_at, :datetime
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..c5befb9 100644
--- a/affordance_request_clean/db/schema.rb
+++ b/affordance_request_clean/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_08_000001) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -73,11 +73,16 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.text "counter_note"
+    t.text "counter_proposal_note"
+    t.datetime "counter_proposed_at"
+    t.datetime "counter_proposed_scheduled_at"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_request_clean/spec/factories/requests.rb b/affordance_request_clean/spec/factories/requests.rb
index c63766e..204fa7c 100644
--- a/affordance_request_clean/spec/factories/requests.rb
+++ b/affordance_request_clean/spec/factories/requests.rb
@@ -34,6 +34,11 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      counter_proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..8dd1247 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -180,4 +180,67 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/requests/:id/counter_propose" do
+    let(:request) { create(:request, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "allows provider to propose a different time" do
+      patch "/api/requests/#{request.id}/counter_propose",
+        params: { proposed_scheduled_at: proposed_time },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("counter_proposed")
+      expect(body["counter_proposed_scheduled_at"]).to be_present
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/requests/#{request.id}/counter_propose", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{request.id}/counter_propose",
+        params: { proposed_scheduled_at: proposed_time },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_counter" do
+    let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+    it "allows client to accept counter-proposal" do
+      patch "/api/requests/#{request.id}/accept_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["state"]).to eq("confirmed")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/accept_counter", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error for non-counter_proposed request" do
+      pending_request = create(:request, client: client, provider: provider)
+      patch "/api/requests/#{pending_request.id}/accept_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_counter" do
+    let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+    it "allows client to decline counter-proposal" do
+      patch "/api/requests/#{request.id}/decline_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["state"]).to eq("canceled")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/decline_counter", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
 end
diff --git a/affordance_request_clean/spec/services/requests/accept_counter_service_spec.rb b/affordance_request_clean/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..21539ff
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,36 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider, counter_proposed_scheduled_at: proposed_time) }
+
+  describe "#call" do
+    it "confirms request and updates scheduled_at to the proposed time" do
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("confirmed")
+      expect(request.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=request_counter_accepted")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-counter_proposed request" do
+      request.update!(state: "pending")
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept counter-proposal")
+    end
+  end
+end
diff --git a/affordance_request_clean/spec/services/requests/counter_propose_service_spec.rb b/affordance_request_clean/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..85cb3e2
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,42 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:request) { create(:request, client: client, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "moves request to counter_proposed state" do
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("counter_proposed")
+      expect(request.reload.counter_proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "notifies the client" do
+      described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(read_notification_log).to include("event=request_counter_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(request: request, provider: other_provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails without proposed time" do
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails for non-pending request" do
+      request.update!(state: "confirmed")
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot counter-propose")
+    end
+  end
+end
diff --git a/affordance_request_clean/spec/services/requests/decline_counter_service_spec.rb b/affordance_request_clean/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..6773914
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,34 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    it "cancels request" do
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("canceled")
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=request_counter_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-counter_proposed request" do
+      request.update!(state: "pending")
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline counter-proposal")
+    end
+  end
+end
```
