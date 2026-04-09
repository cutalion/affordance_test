# Experiment: e03-counter-proposal
# App: app_delta | Model: opus | Run: 1
# Branch: debt_experiment/e03-counter-proposal/app_delta/opus/run-1

---

## Claude Output

All 189 specs pass. Here's a summary of what was implemented:

**Counter-proposal feature for booking requests**

**Database:** Added `proposed_scheduled_at` column to `requests` table.

**Model (`Request`):**
- New `counter_proposed` state
- `counter_propose` event: transitions from `pending` → `counter_proposed`
- `accept` and `decline` events now also transition from `counter_proposed`
- Validation: `proposed_scheduled_at` required when `counter_proposed`

**Services:**
- `Requests::CounterProposeService` — Provider proposes an alternative time for a pending request. Notifies the client.
- `Requests::AcceptCounterProposalService` — Client accepts the counter-proposal. Updates `scheduled_at` to the proposed time, creates an order, and notifies the provider.
- `Requests::DeclineCounterProposalService` — Client declines the counter-proposal (with optional reason). Moves request to `declined` and notifies the provider.

**API endpoints (all PATCH):**
- `PATCH /api/requests/:id/counter_propose` (provider, params: `proposed_scheduled_at`)
- `PATCH /api/requests/:id/accept_counter_proposal` (client)
- `PATCH /api/requests/:id/decline_counter_proposal` (client, optional: `reason`)

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/requests_controller.rb b/app_delta/app/controllers/api/requests_controller.rb
index 9b6998d..1c25dfe 100644
--- a/app_delta/app/controllers/api/requests_controller.rb
+++ b/app_delta/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_counter_proposal, :decline_counter_proposal]
 
     def index
       requests = scoped_requests
@@ -58,6 +58,41 @@ def decline
       handle_service_result(result)
     end
 
+    def counter_propose
+      provider = current_provider!
+      return if performed?
+
+      result = Requests::CounterProposeService.new(
+        request: @request,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at]
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
@@ -103,6 +138,7 @@ def request_detail_json(request)
         duration_minutes: request.duration_minutes,
         location: request.location,
         notes: request.notes,
+        proposed_scheduled_at: request.proposed_scheduled_at,
         decline_reason: request.decline_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
diff --git a/app_delta/app/models/request.rb b/app_delta/app/models/request.rb
index 7f12baf..9bf9a57 100644
--- a/app_delta/app/models/request.rb
+++ b/app_delta/app/models/request.rb
@@ -9,6 +9,7 @@ class Request < ApplicationRecord
   validates :scheduled_at, presence: true
   validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
   validates :decline_reason, presence: true, if: -> { declined? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -28,16 +29,17 @@ class Request < ApplicationRecord
     state :accepted
     state :declined
     state :expired
+    state :counter_proposed
 
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
     end
 
     event :expire do
@@ -46,5 +48,9 @@ class Request < ApplicationRecord
         update!(expired_at: Time.current)
       end
     end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
   end
 end
diff --git a/app_delta/app/services/requests/accept_counter_proposal_service.rb b/app_delta/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..91c06c9
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
+        @request.scheduled_at = @request.proposed_scheduled_at
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
index 0000000..5560162
--- /dev/null
+++ b/app_delta/app/services/requests/counter_propose_service.rb
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
+      @request.proposed_scheduled_at = @proposed_scheduled_at
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
index 0000000..4c48619
--- /dev/null
+++ b/app_delta/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,28 @@
+module Requests
+  class DeclineCounterProposalService
+    def initialize(request:, client:, reason: nil)
+      @request = request
+      @client = client
+      @reason = reason
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("Request has no counter-proposal") unless @request.counter_proposed?
+
+      @request.decline_reason = @reason.presence || "Counter-proposal declined"
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
 
diff --git a/app_delta/db/migrate/20260409140900_add_counter_proposal_to_requests.rb b/app_delta/db/migrate/20260409140900_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..91dd3b8
--- /dev/null
+++ b/app_delta/db/migrate/20260409140900_add_counter_proposal_to_requests.rb
@@ -0,0 +1,5 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index 7580f62..e3afd1f 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_140800) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_140900) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -137,6 +137,7 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
diff --git a/app_delta/spec/factories/requests.rb b/app_delta/spec/factories/requests.rb
index 67c374a..ac50580 100644
--- a/app_delta/spec/factories/requests.rb
+++ b/app_delta/spec/factories/requests.rb
@@ -21,5 +21,10 @@
       state { "expired" }
       expired_at { Time.current }
     end
+
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
   end
 end
diff --git a/app_delta/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_delta/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..c00b7c8
--- /dev/null
+++ b/app_delta/spec/services/requests/accept_counter_proposal_service_spec.rb
@@ -0,0 +1,58 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider, proposed_scheduled_at: proposed_time) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the counter-proposal" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+      end
+
+      it "updates scheduled_at to the proposed time" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "creates an order with the proposed time" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+        order = request.reload.order
+        expect(order).to be_present
+        expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(order.client).to eq(client)
+        expect(order.provider).to eq(provider)
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
index 0000000..db41b8b
--- /dev/null
+++ b/app_delta/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,50 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and proposed time" do
+      it "counter-proposes the request" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(read_notification_log).to include("event=request_counter_proposed")
+      end
+    end
+
+    context "without proposed time" do
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: nil).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
+      end
+    end
+
+    context "with wrong provider" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: other_provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "when already accepted" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_delta/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..ed85a6e
--- /dev/null
+++ b/app_delta/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,48 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "declines the counter-proposal" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_declined
+      end
+
+      it "sets decline reason when provided" do
+        result = described_class.new(request: request, client: client, reason: "Time doesn't work").call
+        expect(result[:success]).to be true
+        expect(request.reload.decline_reason).to eq("Time doesn't work")
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+        expect(read_notification_log).to include("event=counter_proposal_declined")
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
```
