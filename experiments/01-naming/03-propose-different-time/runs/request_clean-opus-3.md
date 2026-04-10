# Experiment: 03-propose-different-time
# App: request_clean | Model: opus | Run: 3
# Branch: experiment/03-propose-different-time/request_clean/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**New state**: `provider_proposed` — sits between `pending` and `confirmed`

**Flow**:
1. Provider calls `PATCH /api/requests/:id/propose_new_time` with `proposed_time` param → request moves to `provider_proposed`, client is notified
2. Client calls `PATCH /api/requests/:id/accept_proposal` → request moves to `confirmed` with the new time as `scheduled_at`
3. Client calls `PATCH /api/requests/:id/decline_proposal` → request returns to `pending` with the original `scheduled_at` restored

**Files changed**:
- Migration adding `proposed_time` and `original_scheduled_at` columns
- `Request` model — new state + 3 AASM events + validation
- `ProposeNewTimeService` — validates provider ownership, parses/validates time, stores original time
- `RespondToProposalService` — accepts or declines, updates scheduled_at accordingly
- Controller + routes — 3 new endpoints
- Full specs (service + request) — all 286 tests pass

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..47d2fc0 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_new_time, :accept_proposal, :decline_proposal]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,42 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_new_time
+      provider = current_provider!
+      return if performed?
+
+      result = Requests::ProposeNewTimeService.new(
+        request: @request,
+        provider: provider,
+        proposed_time: params[:proposed_time]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::RespondToProposalService.new(
+        request: @request,
+        client: client,
+        accept: true
+      ).call
+      handle_service_result(result)
+    end
+
+    def decline_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::RespondToProposalService.new(
+        request: @request,
+        client: client,
+        accept: false
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -141,6 +177,8 @@ def request_detail_json(request)
         currency: request.currency,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_time: request.proposed_time,
+        original_scheduled_at: request.original_scheduled_at,
         started_at: request.started_at,
         completed_at: request.completed_at,
         client_id: request.client_id,
diff --git a/affordance_request_clean/app/models/request.rb b/affordance_request_clean/app/models/request.rb
index 67cb0ca..1ffe681 100644
--- a/affordance_request_clean/app/models/request.rb
+++ b/affordance_request_clean/app/models/request.rb
@@ -13,6 +13,7 @@ class Request < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_time, presence: true, if: -> { provider_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -34,11 +35,24 @@ class Request < ApplicationRecord
     state :completed
     state :canceled
     state :rejected
+    state :provider_proposed
 
     event :confirm do
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_new_time do
+      transitions from: :pending, to: :provider_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :provider_proposed, to: :confirmed
+    end
+
+    event :decline_proposal do
+      transitions from: :provider_proposed, to: :pending
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
diff --git a/affordance_request_clean/app/services/requests/propose_new_time_service.rb b/affordance_request_clean/app/services/requests/propose_new_time_service.rb
new file mode 100644
index 0000000..3211ac7
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/propose_new_time_service.rb
@@ -0,0 +1,39 @@
+module Requests
+  class ProposeNewTimeService
+    def initialize(request:, provider:, proposed_time:)
+      @request = request
+      @provider = provider
+      @proposed_time = proposed_time
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_time.blank?
+
+      parsed_time = parse_time(@proposed_time)
+      return error("Invalid proposed time") unless parsed_time
+      return error("Proposed time must be in the future") unless parsed_time > Time.current
+
+      @request.original_scheduled_at = @request.scheduled_at
+      @request.proposed_time = parsed_time
+      @request.propose_new_time!
+
+      NotificationService.notify(@request.client, :new_time_proposed, request_id: @request.id, proposed_time: parsed_time.iso8601)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot propose new time for request in #{@request.state} state")
+    end
+
+    private
+
+    def parse_time(value)
+      value.is_a?(Time) || value.is_a?(DateTime) ? value : Time.parse(value.to_s)
+    rescue ArgumentError
+      nil
+    end
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/respond_to_proposal_service.rb b/affordance_request_clean/app/services/requests/respond_to_proposal_service.rb
new file mode 100644
index 0000000..928556c
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/respond_to_proposal_service.rb
@@ -0,0 +1,47 @@
+module Requests
+  class RespondToProposalService
+    def initialize(request:, client:, accept:)
+      @request = request
+      @client = client
+      @accept = accept
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      if @accept
+        accept_proposal
+      else
+        decline_proposal
+      end
+    rescue AASM::InvalidTransition
+      error("Cannot respond to proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def accept_proposal
+      @request.scheduled_at = @request.proposed_time
+      @request.proposed_time = nil
+      @request.original_scheduled_at = nil
+      @request.accept_proposal!
+
+      NotificationService.notify(@request.provider, :proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    end
+
+    def decline_proposal
+      @request.scheduled_at = @request.original_scheduled_at if @request.original_scheduled_at
+      @request.proposed_time = nil
+      @request.original_scheduled_at = nil
+      @request.decline_proposal!
+
+      NotificationService.notify(@request.provider, :proposal_declined, request_id: @request.id)
+      { success: true, request: @request }
+    end
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
diff --git a/affordance_request_clean/db/migrate/20260407214324_add_proposed_time_to_requests.rb b/affordance_request_clean/db/migrate/20260407214324_add_proposed_time_to_requests.rb
new file mode 100644
index 0000000..77a2019
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260407214324_add_proposed_time_to_requests.rb
@@ -0,0 +1,6 @@
+class AddProposedTimeToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_time, :datetime
+    add_column :requests, :original_scheduled_at, :datetime
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..4330e46 100644
--- a/affordance_request_clean/db/schema.rb
+++ b/affordance_request_clean/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_214324) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -78,6 +78,9 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "original_scheduled_at"
+    t.datetime "proposed_scheduled_at"
+    t.datetime "proposed_time"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_request_clean/spec/factories/requests.rb b/affordance_request_clean/spec/factories/requests.rb
index c63766e..78b9191 100644
--- a/affordance_request_clean/spec/factories/requests.rb
+++ b/affordance_request_clean/spec/factories/requests.rb
@@ -34,6 +34,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :provider_proposed do
+      state { "provider_proposed" }
+      proposed_time { 5.days.from_now }
+      original_scheduled_at { 3.days.from_now }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..ca18548 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -180,4 +180,62 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/requests/:id/propose_new_time" do
+    let(:request) { create(:request, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "proposes a new time as provider" do
+      patch "/api/requests/#{request.id}/propose_new_time", params: { proposed_time: proposed_time }, headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("provider_proposed")
+      expect(body["proposed_time"]).to be_present
+      expect(body["original_scheduled_at"]).to be_present
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{request.id}/propose_new_time", params: { proposed_time: proposed_time }, headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error without proposed_time" do
+      patch "/api/requests/#{request.id}/propose_new_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_proposal" do
+    let(:request) { create(:request, :provider_proposed, client: client, provider: provider) }
+
+    it "accepts the proposal as client" do
+      patch "/api/requests/#{request.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+      expect(body["proposed_time"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/accept_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_proposal" do
+    let(:request) { create(:request, :provider_proposed, client: client, provider: provider) }
+
+    it "declines the proposal as client" do
+      patch "/api/requests/#{request.id}/decline_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["proposed_time"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/decline_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
 end
diff --git a/affordance_request_clean/spec/services/requests/propose_new_time_service_spec.rb b/affordance_request_clean/spec/services/requests/propose_new_time_service_spec.rb
new file mode 100644
index 0000000..0f2f2d2
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/propose_new_time_service_spec.rb
@@ -0,0 +1,61 @@
+require "rails_helper"
+
+RSpec.describe Requests::ProposeNewTimeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:request) { create(:request, client: client, provider: provider) }
+  let(:proposed_time) { 5.days.from_now.iso8601 }
+
+  describe "#call" do
+    it "proposes a new time for a pending request" do
+      result = described_class.new(request: request, provider: provider, proposed_time: proposed_time).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("provider_proposed")
+      expect(request.proposed_time).to be_present
+      expect(request.original_scheduled_at).to be_present
+    end
+
+    it "saves the original scheduled_at" do
+      original_time = request.scheduled_at
+      described_class.new(request: request, provider: provider, proposed_time: proposed_time).call
+      expect(request.reload.original_scheduled_at).to be_within(1.second).of(original_time)
+    end
+
+    it "notifies the client" do
+      described_class.new(request: request, provider: provider, proposed_time: proposed_time).call
+      expect(read_notification_log).to include("event=new_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(request: request, provider: other_provider, proposed_time: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails without proposed_time" do
+      result = described_class.new(request: request, provider: provider, proposed_time: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails with invalid proposed_time" do
+      result = described_class.new(request: request, provider: provider, proposed_time: "not-a-date").call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Invalid proposed time")
+    end
+
+    it "fails with a past proposed_time" do
+      result = described_class.new(request: request, provider: provider, proposed_time: 1.day.ago.iso8601).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time must be in the future")
+    end
+
+    it "fails for non-pending request" do
+      request.update!(state: "confirmed")
+      result = described_class.new(request: request, provider: provider, proposed_time: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose new time")
+    end
+  end
+end
diff --git a/affordance_request_clean/spec/services/requests/respond_to_proposal_service_spec.rb b/affordance_request_clean/spec/services/requests/respond_to_proposal_service_spec.rb
new file mode 100644
index 0000000..4a68bd3
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/respond_to_proposal_service_spec.rb
@@ -0,0 +1,64 @@
+require "rails_helper"
+
+RSpec.describe Requests::RespondToProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_time) { 3.days.from_now }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) do
+    create(:request, :provider_proposed,
+      client: client,
+      provider: provider,
+      scheduled_at: original_time,
+      proposed_time: proposed_time,
+      original_scheduled_at: original_time)
+  end
+
+  describe "#call" do
+    context "accepting" do
+      it "confirms the request with the proposed time" do
+        result = described_class.new(request: request, client: client, accept: true).call
+        expect(result[:success]).to be true
+        expect(request.reload.state).to eq("confirmed")
+        expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.proposed_time).to be_nil
+        expect(request.original_scheduled_at).to be_nil
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client, accept: true).call
+        expect(read_notification_log).to include("event=proposal_accepted")
+      end
+    end
+
+    context "declining" do
+      it "returns request to pending with original time" do
+        result = described_class.new(request: request, client: client, accept: false).call
+        expect(result[:success]).to be true
+        expect(request.reload.state).to eq("pending")
+        expect(request.scheduled_at).to be_within(1.second).of(original_time)
+        expect(request.proposed_time).to be_nil
+        expect(request.original_scheduled_at).to be_nil
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client, accept: false).call
+        expect(read_notification_log).to include("event=proposal_declined")
+      end
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: request, client: other_client, accept: true).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for non-proposed request" do
+      pending_request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: pending_request, client: client, accept: true).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot respond to proposal")
+    end
+  end
+end
```
