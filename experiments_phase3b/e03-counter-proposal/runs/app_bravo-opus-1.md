# Experiment: e03-counter-proposal
# App: app_bravo | Model: opus | Run: 1
# Branch: debt_experiment/e03-counter-proposal/app_bravo/opus/run-1

---

## Claude Output

All 141 tests pass. Here's a summary of what was implemented:

**Migration**: Added `proposed_scheduled_at` (datetime) and `proposal_reason` (text) to `requests` table.

**Request model** (`app/models/request.rb`):
- New `counter_proposed` state
- `counter_propose` event: transitions from `pending` → `counter_proposed`
- `accept` now also transitions from `counter_proposed` → `accepted`
- `decline` now also transitions from `counter_proposed` → `declined`
- Validates `proposed_scheduled_at` presence when counter-proposed

**Three new services**:
- `Requests::CounterProposeService` — provider proposes a different time (with optional reason)
- `Requests::AcceptCounterProposalService` — client accepts, updating `scheduled_at` to the proposed time and creating an order
- `Requests::DeclineCounterProposalService` — client declines with a reason

**API endpoints** (all PATCH):
- `PATCH /api/requests/:id/counter_propose` — provider sends `proposed_scheduled_at` and optional `reason`
- `PATCH /api/requests/:id/accept_counter_proposal` — client accepts
- `PATCH /api/requests/:id/decline_counter_proposal` — client sends `reason`

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/requests_controller.rb b/app_bravo/app/controllers/api/requests_controller.rb
index 9b6998d..ceb1fe7 100644
--- a/app_bravo/app/controllers/api/requests_controller.rb
+++ b/app_bravo/app/controllers/api/requests_controller.rb
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
+        proposed_scheduled_at: params[:proposed_scheduled_at],
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
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        proposal_reason: request.proposal_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         client_id: request.client_id,
diff --git a/app_bravo/app/models/request.rb b/app_bravo/app/models/request.rb
index 7f12baf..9bf9a57 100644
--- a/app_bravo/app/models/request.rb
+++ b/app_bravo/app/models/request.rb
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
diff --git a/app_bravo/app/services/requests/accept_counter_proposal_service.rb b/app_bravo/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..72a98da
--- /dev/null
+++ b/app_bravo/app/services/requests/accept_counter_proposal_service.rb
@@ -0,0 +1,46 @@
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
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_bravo/app/services/requests/counter_propose_service.rb b/app_bravo/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..cf6c2d0
--- /dev/null
+++ b/app_bravo/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,30 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_scheduled_at:, reason: nil)
+      @request = request
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+      @reason = reason
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @request.proposed_scheduled_at = @proposed_scheduled_at
+      @request.proposal_reason = @reason
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
diff --git a/app_bravo/app/services/requests/decline_counter_proposal_service.rb b/app_bravo/app/services/requests/decline_counter_proposal_service.rb
new file mode 100644
index 0000000..93baa93
--- /dev/null
+++ b/app_bravo/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,27 @@
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
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_bravo/config/routes.rb b/app_bravo/config/routes.rb
index 8d32af9..520b5ca 100644
--- a/app_bravo/config/routes.rb
+++ b/app_bravo/config/routes.rb
@@ -14,6 +14,9 @@
       member do
         patch :accept
         patch :decline
+        patch :counter_propose
+        patch :accept_counter_proposal
+        patch :decline_counter_proposal
       end
     end
 
diff --git a/app_bravo/db/migrate/20260409144823_add_counter_proposal_to_requests.rb b/app_bravo/db/migrate/20260409144823_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..4034233
--- /dev/null
+++ b/app_bravo/db/migrate/20260409144823_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :proposal_reason, :text
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index 667709c..857bcd5 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_075820) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_144823) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -115,6 +115,8 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_reason"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.integer "recurring_booking_id"
     t.datetime "scheduled_at", null: false
diff --git a/app_bravo/spec/factories/requests.rb b/app_bravo/spec/factories/requests.rb
index 67c374a..1717797 100644
--- a/app_bravo/spec/factories/requests.rb
+++ b/app_bravo/spec/factories/requests.rb
@@ -21,5 +21,11 @@
       state { "expired" }
       expired_at { Time.current }
     end
+
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      proposal_reason { "I'm unavailable at the requested time" }
+    end
   end
 end
diff --git a/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..0d7ff90
--- /dev/null
+++ b/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb
@@ -0,0 +1,64 @@
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
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+      end
+
+      it "updates scheduled_at to the proposed time" do
+        described_class.new(request: request, client: client).call
+
+        expect(request.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "creates an order linked to the request" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+
+        order = request.reload.order
+        expect(order).to be_present
+        expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(order.client).to eq(client)
+        expect(order.provider).to eq(provider)
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+
+        expect(read_notification_log).to include("event=counter_proposal_accepted")
+      end
+    end
+
+    context "with wrong client" do
+      let(:other_client) { create(:client) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: other_client).call
+
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
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("no counter-proposal")
+      end
+    end
+  end
+end
diff --git a/app_bravo/spec/services/requests/counter_propose_service_spec.rb b/app_bravo/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..97eff37
--- /dev/null
+++ b/app_bravo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,88 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider" do
+      it "counter-proposes the request" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy that day"
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.proposal_reason).to eq("I'm busy that day")
+      end
+
+      it "notifies the client" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
+        expect(read_notification_log).to include("event=request_counter_proposed")
+      end
+
+      it "works without a reason" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload.proposal_reason).to be_nil
+      end
+    end
+
+    context "with wrong provider" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(
+          request: request,
+          provider: other_provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "without proposed time" do
+      it "returns error" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: nil
+        ).call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
+      end
+    end
+
+    context "when already accepted" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..6a4a6e8
--- /dev/null
+++ b/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,56 @@
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
+        result = described_class.new(request: request, client: client, reason: "Time doesn't work").call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_declined
+        expect(request.decline_reason).to eq("Time doesn't work")
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client, reason: "Time doesn't work").call
+
+        expect(read_notification_log).to include("event=counter_proposal_declined")
+      end
+    end
+
+    context "with wrong client" do
+      let(:other_client) { create(:client) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: other_client, reason: "No").call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "without reason" do
+      it "returns error" do
+        result = described_class.new(request: request, client: client, reason: "").call
+
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
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("no counter-proposal")
+      end
+    end
+  end
+end
```
