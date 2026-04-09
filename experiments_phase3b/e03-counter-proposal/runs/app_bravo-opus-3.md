# Experiment: e03-counter-proposal
# App: app_bravo | Model: opus | Run: 3
# Branch: debt_experiment/e03-counter-proposal/app_bravo/opus/run-3

---

## Claude Output

All done. Here's a summary of what was implemented:

**Counter-proposal feature for booking requests**

**New state flow:**
- `pending` → `counter_proposed` (provider proposes a different time)
- `counter_proposed` → `accepted` (client accepts; `scheduled_at` updated to proposed time, order created)
- `counter_proposed` → `pending` (client declines; proposal fields cleared, allowing further negotiation)

**Files changed:**
- `db/migrate/20260409145604_add_counter_proposal_fields_to_requests.rb` — adds `proposed_scheduled_at` and `proposal_reason` columns
- `app/models/request.rb` — new `counter_proposed` state, three new AASM events, validation
- `app/services/requests/counter_propose_service.rb` — provider action, sets proposed time and notifies client
- `app/services/requests/accept_counter_proposal_service.rb` — client action, accepts proposed time, creates order
- `app/services/requests/decline_counter_proposal_service.rb` — client action, returns to pending
- `app/controllers/api/requests_controller.rb` — three new endpoints
- `config/routes.rb` — three new member routes

**New API endpoints:**
- `PATCH /api/requests/:id/counter_propose` (provider, params: `proposed_scheduled_at`, `reason`)
- `PATCH /api/requests/:id/accept_counter_proposal` (client)
- `PATCH /api/requests/:id/decline_counter_proposal` (client)

**Tests:** 147 examples, 0 failures.

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/requests_controller.rb b/app_bravo/app/controllers/api/requests_controller.rb
index 9b6998d..aea3256 100644
--- a/app_bravo/app/controllers/api/requests_controller.rb
+++ b/app_bravo/app/controllers/api/requests_controller.rb
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
+      result = Requests::DeclineCounterProposalService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -104,6 +139,8 @@ def request_detail_json(request)
         location: request.location,
         notes: request.notes,
         decline_reason: request.decline_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        proposal_reason: request.proposal_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         client_id: request.client_id,
diff --git a/app_bravo/app/models/request.rb b/app_bravo/app/models/request.rb
index 7f12baf..494666b 100644
--- a/app_bravo/app/models/request.rb
+++ b/app_bravo/app/models/request.rb
@@ -9,6 +9,7 @@ class Request < ApplicationRecord
   validates :scheduled_at, presence: true
   validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
   validates :decline_reason, presence: true, if: -> { declined? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -27,6 +28,7 @@ class Request < ApplicationRecord
     state :pending, initial: true
     state :accepted
     state :declined
+    state :counter_proposed
     state :expired
 
     event :accept do
@@ -40,6 +42,24 @@ class Request < ApplicationRecord
       transitions from: :pending, to: :declined
     end
 
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_counter_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(scheduled_at: proposed_scheduled_at, accepted_at: Time.current)
+      end
+    end
+
+    event :decline_counter_proposal do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil, proposal_reason: nil)
+      end
+    end
+
     event :expire do
       transitions from: :pending, to: :expired
       after do
diff --git a/app_bravo/app/services/requests/accept_counter_proposal_service.rb b/app_bravo/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..17d5030
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
+
+      Request.transaction do
+        @request.accept_counter_proposal!
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
diff --git a/app_bravo/app/services/requests/counter_propose_service.rb b/app_bravo/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..025e542
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
+      NotificationService.notify(@request.client, :counter_proposal, request_id: @request.id)
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
index 0000000..080bd72
--- /dev/null
+++ b/app_bravo/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,25 @@
+module Requests
+  class DeclineCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.decline_counter_proposal!
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
 
diff --git a/app_bravo/db/migrate/20260409145604_add_counter_proposal_fields_to_requests.rb b/app_bravo/db/migrate/20260409145604_add_counter_proposal_fields_to_requests.rb
new file mode 100644
index 0000000..7ae5f87
--- /dev/null
+++ b/app_bravo/db/migrate/20260409145604_add_counter_proposal_fields_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalFieldsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime unless column_exists?(:requests, :proposed_scheduled_at)
+    add_column :requests, :proposal_reason, :text unless column_exists?(:requests, :proposal_reason)
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index 667709c..ee353de 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_075820) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_145604) do
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
index 67c374a..db7e3b1 100644
--- a/app_bravo/spec/factories/requests.rb
+++ b/app_bravo/spec/factories/requests.rb
@@ -17,6 +17,12 @@
       decline_reason { "Not available" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      proposal_reason { "I'm busy that day, how about this time?" }
+    end
+
     trait :expired do
       state { "expired" }
       expired_at { Time.current }
diff --git a/app_bravo/spec/models/request_spec.rb b/app_bravo/spec/models/request_spec.rb
index dec4a53..2001aa5 100644
--- a/app_bravo/spec/models/request_spec.rb
+++ b/app_bravo/spec/models/request_spec.rb
@@ -23,6 +23,13 @@
         expect(request).not_to be_valid
       end
     end
+
+    context "when counter_proposed" do
+      it "requires proposed_scheduled_at" do
+        request = build(:request, :counter_proposed, proposed_scheduled_at: nil)
+        expect(request).not_to be_valid
+      end
+    end
   end
 
   describe "state machine" do
@@ -65,6 +72,57 @@
       end
     end
 
+    describe "counter_propose event" do
+      it "transitions from pending to counter_proposed" do
+        request.proposed_scheduled_at = 5.days.from_now
+        request.counter_propose!
+        expect(request).to be_counter_proposed
+      end
+
+      it "cannot counter-propose from accepted" do
+        request.accept!
+        expect { request.counter_propose! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_counter_proposal event" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to accepted" do
+        counter_proposed_request.accept_counter_proposal!
+        expect(counter_proposed_request).to be_accepted
+      end
+
+      it "updates scheduled_at to proposed_scheduled_at" do
+        proposed = counter_proposed_request.proposed_scheduled_at
+        counter_proposed_request.accept_counter_proposal!
+        expect(counter_proposed_request.reload.scheduled_at).to be_within(1.second).of(proposed)
+      end
+
+      it "cannot accept counter-proposal from pending" do
+        expect { request.accept_counter_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_counter_proposal event" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to pending" do
+        counter_proposed_request.decline_counter_proposal!
+        expect(counter_proposed_request).to be_pending
+      end
+
+      it "clears proposal fields" do
+        counter_proposed_request.decline_counter_proposal!
+        expect(counter_proposed_request.reload.proposed_scheduled_at).to be_nil
+        expect(counter_proposed_request.proposal_reason).to be_nil
+      end
+
+      it "cannot decline counter-proposal from pending" do
+        expect { request.decline_counter_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
     describe "expire event" do
       it "transitions from pending to expired" do
         request.expire!
diff --git a/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..bc20d8d
--- /dev/null
+++ b/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb
@@ -0,0 +1,54 @@
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
+      it "accepts the counter-proposal and updates scheduled_at" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+        expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.accepted_at).to be_present
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
+    context "when request is not counter_proposed" do
+      let(:pending_request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_bravo/spec/services/requests/counter_propose_service_spec.rb b/app_bravo/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..79aa41b
--- /dev/null
+++ b/app_bravo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,72 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and proposed time" do
+      it "transitions request to counter_proposed" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy that day"
+        ).call
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
+        expect(read_notification_log).to include("event=counter_proposal")
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
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
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
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "when request is not pending" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..08ea364
--- /dev/null
+++ b/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,43 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns request to pending and clears proposal fields" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.proposal_reason).to be_nil
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
+    context "when request is not counter_proposed" do
+      let(:pending_request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
