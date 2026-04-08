# Experiment: 03-propose-different-time
# App: request_clean | Model: sonnet | Run: 1
# Branch: experiment/03-propose-different-time/request_clean/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**New state flow:**
- `pending` → `countered` (provider calls `propose_time`)
- `countered` → `confirmed` (client calls `accept_counter`, scheduled_at is updated to the proposed time)
- `countered` → `canceled` (client calls `decline_counter`)

**New DB columns:** `proposed_scheduled_at`, `counter_note`

**New services:**
- `Requests::ProposeTimeService` — provider proposes a new time with optional note
- `Requests::AcceptCounterService` — client accepts, confirms the request at the new time
- `Requests::DeclineCounterService` — client declines, cancels the request

**New API endpoints:**
- `PATCH /api/requests/:id/propose_time` (provider only, requires `proposed_scheduled_at`, optional `note`)
- `PATCH /api/requests/:id/accept_counter` (client only)
- `PATCH /api/requests/:id/decline_counter` (client only)

All 291 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..07e8a9d 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_time, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,39 @@ def reject
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
+        request: @request,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at],
+        note: params[:note]
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
@@ -141,6 +174,8 @@ def request_detail_json(request)
         currency: request.currency,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        counter_note: request.counter_note,
         started_at: request.started_at,
         completed_at: request.completed_at,
         client_id: request.client_id,
diff --git a/affordance_request_clean/app/models/request.rb b/affordance_request_clean/app/models/request.rb
index 67cb0ca..19499ca 100644
--- a/affordance_request_clean/app/models/request.rb
+++ b/affordance_request_clean/app/models/request.rb
@@ -13,6 +13,7 @@ class Request < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { countered? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -29,6 +30,7 @@ class Request < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :countered
     state :confirmed
     state :in_progress
     state :completed
@@ -39,6 +41,21 @@ class Request < ApplicationRecord
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_time do
+      transitions from: :pending, to: :countered
+    end
+
+    event :accept_counter do
+      transitions from: :countered, to: :confirmed
+      after do
+        update!(scheduled_at: proposed_scheduled_at)
+      end
+    end
+
+    event :decline_counter do
+      transitions from: :countered, to: :canceled
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
diff --git a/affordance_request_clean/app/services/requests/accept_counter_service.rb b/affordance_request_clean/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..58f432f
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
+      NotificationService.notify(@request.provider, :counter_proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter-proposal for request in #{@request.state} state")
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
index 0000000..262caf7
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
+      NotificationService.notify(@request.provider, :counter_proposal_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline counter-proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/propose_time_service.rb b/affordance_request_clean/app/services/requests/propose_time_service.rb
new file mode 100644
index 0000000..907720c
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/propose_time_service.rb
@@ -0,0 +1,30 @@
+module Requests
+  class ProposeTimeService
+    def initialize(request:, provider:, proposed_scheduled_at:, note: nil)
+      @request = request
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+      @note = note
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @request.proposed_scheduled_at = @proposed_scheduled_at
+      @request.counter_note = @note
+      @request.propose_time!
+
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
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..88b893e 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -17,6 +17,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :propose_time
+        patch :accept_counter
+        patch :decline_counter
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request_clean/db/migrate/20260408000001_add_counter_proposal_to_requests.rb b/affordance_request_clean/db/migrate/20260408000001_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..432882a
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260408000001_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :counter_note, :text
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..564a379 100644
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
@@ -73,11 +73,13 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.text "counter_note"
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
index c63766e..cee86fb 100644
--- a/affordance_request_clean/spec/factories/requests.rb
+++ b/affordance_request_clean/spec/factories/requests.rb
@@ -13,6 +13,11 @@
       state { "confirmed" }
     end
 
+    trait :countered do
+      state { "countered" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :in_progress do
       state { "in_progress" }
       started_at { Time.current }
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..dd917c3 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -180,4 +180,88 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/requests/:id/propose_time" do
+    let(:request) { create(:request, client: client, provider: provider) }
+    let(:new_time) { 5.days.from_now.iso8601 }
+
+    it "transitions request to countered state" do
+      patch "/api/requests/#{request.id}/propose_time",
+        params: { proposed_scheduled_at: new_time },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("countered")
+      expect(body["proposed_scheduled_at"]).to be_present
+    end
+
+    it "accepts an optional note" do
+      patch "/api/requests/#{request.id}/propose_time",
+        params: { proposed_scheduled_at: new_time, note: "Busy that day" },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["counter_note"]).to eq("Busy that day")
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/requests/#{request.id}/propose_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{request.id}/propose_time",
+        params: { proposed_scheduled_at: new_time },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_counter" do
+    let(:request) do
+      create(:request, client: client, provider: provider,
+        state: "countered", proposed_scheduled_at: 5.days.from_now)
+    end
+
+    it "confirms request with the proposed time" do
+      patch "/api/requests/#{request.id}/accept_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/accept_counter", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error for non-countered request" do
+      pending_request = create(:request, client: client, provider: provider)
+      patch "/api/requests/#{pending_request.id}/accept_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_counter" do
+    let(:request) do
+      create(:request, client: client, provider: provider,
+        state: "countered", proposed_scheduled_at: 5.days.from_now)
+    end
+
+    it "cancels request when client declines counter-proposal" do
+      patch "/api/requests/#{request.id}/decline_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["state"]).to eq("canceled")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/decline_counter", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error for non-countered request" do
+      pending_request = create(:request, client: client, provider: provider)
+      patch "/api/requests/#{pending_request.id}/decline_counter", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
diff --git a/affordance_request_clean/spec/services/requests/accept_counter_service_spec.rb b/affordance_request_clean/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..15e00e7
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,43 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:new_time) { 5.days.from_now }
+  let(:request) do
+    create(:request, client: client, provider: provider,
+      state: "countered", proposed_scheduled_at: new_time)
+  end
+
+  describe "#call" do
+    it "transitions request to confirmed state" do
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("confirmed")
+    end
+
+    it "applies the proposed time as the new scheduled_at" do
+      described_class.new(request: request, client: client).call
+      expect(request.reload.scheduled_at).to be_within(1.second).of(new_time)
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=counter_proposal_accepted")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-countered request" do
+      request.update!(state: "pending")
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept counter-proposal")
+    end
+  end
+end
diff --git a/affordance_request_clean/spec/services/requests/decline_counter_service_spec.rb b/affordance_request_clean/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..3530cf8
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,37 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request, client: client, provider: provider,
+      state: "countered", proposed_scheduled_at: 5.days.from_now)
+  end
+
+  describe "#call" do
+    it "transitions request to canceled state" do
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("canceled")
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=counter_proposal_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-countered request" do
+      request.update!(state: "pending")
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline counter-proposal")
+    end
+  end
+end
diff --git a/affordance_request_clean/spec/services/requests/propose_time_service_spec.rb b/affordance_request_clean/spec/services/requests/propose_time_service_spec.rb
new file mode 100644
index 0000000..2d41b92
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/propose_time_service_spec.rb
@@ -0,0 +1,51 @@
+require "rails_helper"
+
+RSpec.describe Requests::ProposeTimeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:request) { create(:request, client: client, provider: provider) }
+  let(:new_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "transitions request to countered state" do
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: new_time).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("countered")
+    end
+
+    it "saves the proposed time" do
+      described_class.new(request: request, provider: provider, proposed_scheduled_at: new_time).call
+      expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(new_time)
+    end
+
+    it "saves the optional note" do
+      described_class.new(request: request, provider: provider, proposed_scheduled_at: new_time, note: "Sorry, busy that day").call
+      expect(request.reload.counter_note).to eq("Sorry, busy that day")
+    end
+
+    it "notifies the client" do
+      described_class.new(request: request, provider: provider, proposed_scheduled_at: new_time).call
+      expect(read_notification_log).to include("event=request_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(request: request, provider: other_provider, proposed_scheduled_at: new_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails when proposed time is blank" do
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails for non-pending request" do
+      request.update!(state: "confirmed")
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: new_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose a different time")
+    end
+  end
+end
```
