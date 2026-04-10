# Experiment: e03-counter-proposal
# App: app_delta | Model: opus | Run: 3
# Branch: debt_experiment/e03-counter-proposal/app_delta/opus/run-3

---

## Claude Output

All 189 tests pass. Here's a summary of what was implemented:

**Migration**: Added `proposed_time` (datetime) and `counter_proposal_reason` (text) columns to the `requests` table.

**Model changes** (`app/models/request.rb`):
- New `counter_proposed` state in the AASM state machine
- `counter_propose` event: transitions from `pending` → `counter_proposed`
- `accept` and `decline` events now also transition from `counter_proposed` (so the client can accept/decline the counter-proposal)
- Validations requiring `proposed_time` and `counter_proposal_reason` when in the `counter_proposed` state

**New services**:
- `Requests::CounterProposeService` — provider proposes a different time with a reason; notifies the client
- `Requests::AcceptCounterProposalService` — client accepts; updates `scheduled_at` to the proposed time, creates an order, notifies the provider
- `Requests::DeclineCounterProposalService` — client declines with a reason; notifies the provider

**API endpoints** (all `PATCH`):
- `PATCH /api/requests/:id/counter_propose` — provider sends `proposed_time` and `reason`
- `PATCH /api/requests/:id/accept_counter_proposal` — client accepts
- `PATCH /api/requests/:id/decline_counter_proposal` — client sends `reason`

**JSON response** now includes `proposed_time` and `counter_proposal_reason` fields.

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/requests_controller.rb b/app_delta/app/controllers/api/requests_controller.rb
index 9b6998d..03df7db 100644
--- a/app_delta/app/controllers/api/requests_controller.rb
+++ b/app_delta/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_counter_proposal, :decline_counter_proposal]
 
     def index
       requests = scoped_requests
@@ -58,6 +58,46 @@ def decline
       handle_service_result(result)
     end
 
+    def counter_propose
+      provider = current_provider!
+      return if performed?
+
+      result = Requests::CounterProposeService.new(
+        request: @request,
+        provider: provider,
+        proposed_time: params[:proposed_time],
+        reason: params[:reason]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptCounterProposalService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
+    def decline_counter_proposal
+      client = current_client!
+      return if performed?
+
+      if params[:reason].blank?
+        return render_unprocessable(["Reason is required"])
+      end
+
+      result = Requests::DeclineCounterProposalService.new(
+        request: @request,
+        client: client,
+        reason: params[:reason]
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -104,6 +144,8 @@ def request_detail_json(request)
         location: request.location,
         notes: request.notes,
         decline_reason: request.decline_reason,
+        proposed_time: request.proposed_time,
+        counter_proposal_reason: request.counter_proposal_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         client_id: request.client_id,
diff --git a/app_delta/app/models/request.rb b/app_delta/app/models/request.rb
index 7f12baf..008fb96 100644
--- a/app_delta/app/models/request.rb
+++ b/app_delta/app/models/request.rb
@@ -9,6 +9,8 @@ class Request < ApplicationRecord
   validates :scheduled_at, presence: true
   validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
   validates :decline_reason, presence: true, if: -> { declined? }
+  validates :proposed_time, presence: true, if: -> { counter_proposed? }
+  validates :counter_proposal_reason, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -27,17 +29,22 @@ class Request < ApplicationRecord
     state :pending, initial: true
     state :accepted
     state :declined
+    state :counter_proposed
     state :expired
 
     event :accept do
-      transitions from: :pending, to: :accepted
+      transitions from: [:pending, :counter_proposed], to: :accepted
       after do
         update!(accepted_at: Time.current)
       end
     end
 
     event :decline do
-      transitions from: :pending, to: :declined
+      transitions from: [:pending, :counter_proposed], to: :declined
+    end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
     end
 
     event :expire do
diff --git a/app_delta/app/services/requests/accept_counter_proposal_service.rb b/app_delta/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..f6ebbe4
--- /dev/null
+++ b/app_delta/app/services/requests/accept_counter_proposal_service.rb
@@ -0,0 +1,48 @@
+module Requests
+  class AcceptCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("Request has no counter-proposal") unless @request.counter_proposed?
+
+      Request.transaction do
+        @request.scheduled_at = @request.proposed_time
+        @request.accept!
+
+        order_result = Orders::CreateService.new(
+          client: @request.client,
+          provider: @request.provider,
+          params: {
+            scheduled_at: @request.scheduled_at,
+            duration_minutes: @request.duration_minutes,
+            location: @request.location,
+            notes: @request.notes,
+            amount_cents: 350_000,
+            currency: "RUB"
+          },
+          request: @request
+        ).call
+
+        unless order_result[:success]
+          raise ActiveRecord::Rollback
+          return error("Failed to create order")
+        end
+      end
+
+      NotificationService.notify(@request.provider, :counter_proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter-proposal in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_delta/app/services/requests/counter_propose_service.rb b/app_delta/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..93d1217
--- /dev/null
+++ b/app_delta/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,31 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_time:, reason:)
+      @request = request
+      @provider = provider
+      @proposed_time = proposed_time
+      @reason = reason
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_time.blank?
+      return error("Reason is required") if @reason.blank?
+
+      @request.proposed_time = @proposed_time
+      @request.counter_proposal_reason = @reason
+      @request.counter_propose!
+
+      NotificationService.notify(@request.client, :request_counter_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot counter-propose for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_delta/app/services/requests/decline_counter_proposal_service.rb b/app_delta/app/services/requests/decline_counter_proposal_service.rb
new file mode 100644
index 0000000..084a253
--- /dev/null
+++ b/app_delta/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,29 @@
+module Requests
+  class DeclineCounterProposalService
+    def initialize(request:, client:, reason:)
+      @request = request
+      @client = client
+      @reason = reason
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("Request has no counter-proposal") unless @request.counter_proposed?
+      return error("Decline reason is required") if @reason.blank?
+
+      @request.decline_reason = @reason
+      @request.decline!
+
+      NotificationService.notify(@request.provider, :counter_proposal_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline counter-proposal in #{@request.state} state")
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
index d9e099b..abc4fee 100644
--- a/app_delta/config/routes.rb
+++ b/app_delta/config/routes.rb
@@ -14,6 +14,9 @@
       member do
         patch :accept
         patch :decline
+        patch :counter_propose
+        patch :accept_counter_proposal
+        patch :decline_counter_proposal
       end
     end
 
diff --git a/app_delta/db/migrate/20260410120000_add_counter_proposal_to_requests.rb b/app_delta/db/migrate/20260410120000_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..5429201
--- /dev/null
+++ b/app_delta/db/migrate/20260410120000_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_time, :datetime
+    add_column :requests, :counter_proposal_reason, :text
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index c5b443e..f5ce359 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -113,12 +113,14 @@
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "client_id", null: false
+    t.text "counter_proposal_reason"
     t.datetime "created_at", null: false
     t.text "decline_reason"
     t.integer "duration_minutes", null: false
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_time"
     t.integer "provider_id", null: false
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
diff --git a/app_delta/spec/factories/requests.rb b/app_delta/spec/factories/requests.rb
index 67c374a..65b9982 100644
--- a/app_delta/spec/factories/requests.rb
+++ b/app_delta/spec/factories/requests.rb
@@ -17,6 +17,12 @@
       decline_reason { "Not available" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_time { 5.days.from_now }
+      counter_proposal_reason { "I'm busy that day, how about later?" }
+    end
+
     trait :expired do
       state { "expired" }
       expired_at { Time.current }
diff --git a/app_delta/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_delta/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..d4fc1a3
--- /dev/null
+++ b/app_delta/spec/services/requests/accept_counter_proposal_service_spec.rb
@@ -0,0 +1,51 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the request and updates scheduled_at to proposed_time" do
+        proposed = request.proposed_time
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+        expect(request.scheduled_at).to be_within(1.second).of(proposed)
+      end
+
+      it "creates an order with the proposed time" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+        order = request.reload.order
+        expect(order.scheduled_at).to be_within(1.second).of(request.proposed_time)
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+        expect(read_notification_log).to include("event=counter_proposal_accepted")
+      end
+    end
+
+    context "with wrong client" do
+      let(:other_client) { create(:client) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: other_client).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "when request is not counter-proposed" do
+      let(:pending_request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("no counter-proposal")
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/requests/counter_propose_service_spec.rb b/app_delta/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..a470d1e
--- /dev/null
+++ b/app_delta/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,77 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with valid params" do
+      it "counter-proposes the request" do
+        result = described_class.new(
+          request: request, provider: provider,
+          proposed_time: proposed_time, reason: "Busy that day"
+        ).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_time).to be_within(1.second).of(proposed_time)
+        expect(request.counter_proposal_reason).to eq("Busy that day")
+      end
+
+      it "notifies the client" do
+        described_class.new(
+          request: request, provider: provider,
+          proposed_time: proposed_time, reason: "Busy that day"
+        ).call
+        expect(read_notification_log).to include("event=request_counter_proposed")
+      end
+    end
+
+    context "with wrong provider" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(
+          request: request, provider: other_provider,
+          proposed_time: proposed_time, reason: "Busy"
+        ).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "without proposed_time" do
+      it "returns error" do
+        result = described_class.new(
+          request: request, provider: provider,
+          proposed_time: nil, reason: "Busy"
+        ).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
+      end
+    end
+
+    context "without reason" do
+      it "returns error" do
+        result = described_class.new(
+          request: request, provider: provider,
+          proposed_time: proposed_time, reason: nil
+        ).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Reason is required")
+      end
+    end
+
+    context "when already accepted" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(
+          request: request, provider: provider,
+          proposed_time: proposed_time, reason: "Busy"
+        ).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_delta/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..6879c15
--- /dev/null
+++ b/app_delta/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,51 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client and reason" do
+      it "declines the request" do
+        result = described_class.new(request: request, client: client, reason: "Time doesn't work").call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_declined
+        expect(request.decline_reason).to eq("Time doesn't work")
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client, reason: "Time doesn't work").call
+        expect(read_notification_log).to include("event=counter_proposal_declined")
+      end
+    end
+
+    context "with wrong client" do
+      let(:other_client) { create(:client) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: other_client, reason: "No").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "without reason" do
+      it "returns error" do
+        result = described_class.new(request: request, client: client, reason: nil).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Decline reason is required")
+      end
+    end
+
+    context "when request is not counter-proposed" do
+      let(:pending_request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client, reason: "No").call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("no counter-proposal")
+      end
+    end
+  end
+end
```
