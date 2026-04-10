# Experiment: e03-counter-proposal
# App: app_bravo | Model: opus | Run: 3
# Branch: debt_experiment/e03-counter-proposal/app_bravo/opus/run-3

---

## Claude Output

All 151 tests pass (including the new ones). Here's a summary of what was implemented:

**Counter-proposal feature for booking requests**

**New state flow:**
- `pending` → `counter_proposed` (provider proposes a different time with a reason)
- `counter_proposed` → `accepted` (client accepts — updates `scheduled_at` to the proposed time, creates an order)
- `counter_proposed` → `pending` (client declines — clears proposal fields, provider can try again)

**Changes made:**

| File | Change |
|------|--------|
| `db/migrate/20260410120000_add_counter_proposal_to_requests.rb` | Adds `proposed_at` and `proposal_reason` columns |
| `app/models/request.rb` | New `counter_proposed` state, three new events (`counter_propose`, `accept_proposal`, `decline_proposal`), validations |
| `app/services/requests/counter_propose_service.rb` | Provider proposes a new time with reason; notifies client |
| `app/services/requests/accept_proposal_service.rb` | Client accepts counter-proposal; updates scheduled time, creates order + payment; notifies provider |
| `app/services/requests/decline_proposal_service.rb` | Client declines counter-proposal; returns request to pending; notifies provider |
| `config/routes.rb` | Three new member routes: `counter_propose`, `accept_proposal`, `decline_proposal` |
| `app/controllers/api/requests_controller.rb` | Three new actions + proposal fields in JSON response |
| `spec/` | Model specs for new transitions, service specs for all three services, factory trait |

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/requests_controller.rb b/app_bravo/app/controllers/api/requests_controller.rb
index 9b6998d..1f8f4f2 100644
--- a/app_bravo/app/controllers/api/requests_controller.rb
+++ b/app_bravo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_proposal, :decline_proposal]
 
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
+        proposed_at: params[:proposed_at],
+        reason: params[:reason]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptProposalService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
+    def decline_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineProposalService.new(
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
+        proposed_at: request.proposed_at,
+        proposal_reason: request.proposal_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         client_id: request.client_id,
diff --git a/app_bravo/app/models/request.rb b/app_bravo/app/models/request.rb
index 7f12baf..9ba4dbd 100644
--- a/app_bravo/app/models/request.rb
+++ b/app_bravo/app/models/request.rb
@@ -9,6 +9,8 @@ class Request < ApplicationRecord
   validates :scheduled_at, presence: true
   validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
   validates :decline_reason, presence: true, if: -> { declined? }
+  validates :proposed_at, presence: true, if: -> { counter_proposed? }
+  validates :proposal_reason, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -28,6 +30,7 @@ class Request < ApplicationRecord
     state :accepted
     state :declined
     state :expired
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -46,5 +49,23 @@ class Request < ApplicationRecord
         update!(expired_at: Time.current)
       end
     end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(scheduled_at: proposed_at, accepted_at: Time.current)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_at: nil, proposal_reason: nil)
+      end
+    end
   end
 end
diff --git a/app_bravo/app/services/requests/accept_proposal_service.rb b/app_bravo/app/services/requests/accept_proposal_service.rb
new file mode 100644
index 0000000..951dc5f
--- /dev/null
+++ b/app_bravo/app/services/requests/accept_proposal_service.rb
@@ -0,0 +1,46 @@
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
+      Request.transaction do
+        @request.accept_proposal!
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
+      NotificationService.notify(@request.provider, :proposal_accepted, request_id: @request.id)
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
diff --git a/app_bravo/app/services/requests/counter_propose_service.rb b/app_bravo/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..9908a05
--- /dev/null
+++ b/app_bravo/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,31 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_at:, reason:)
+      @request = request
+      @provider = provider
+      @proposed_at = proposed_at
+      @reason = reason
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_at.blank?
+      return error("Reason is required") if @reason.blank?
+
+      @request.proposed_at = @proposed_at
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
diff --git a/app_bravo/app/services/requests/decline_proposal_service.rb b/app_bravo/app/services/requests/decline_proposal_service.rb
new file mode 100644
index 0000000..71260ea
--- /dev/null
+++ b/app_bravo/app/services/requests/decline_proposal_service.rb
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
+
+      @request.decline_proposal!
+
+      NotificationService.notify(@request.provider, :proposal_declined, request_id: @request.id)
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
diff --git a/app_bravo/config/routes.rb b/app_bravo/config/routes.rb
index 8d32af9..9b06064 100644
--- a/app_bravo/config/routes.rb
+++ b/app_bravo/config/routes.rb
@@ -14,6 +14,9 @@
       member do
         patch :accept
         patch :decline
+        patch :counter_propose
+        patch :accept_proposal
+        patch :decline_proposal
       end
     end
 
diff --git a/app_bravo/db/migrate/20260410120000_add_counter_proposal_to_requests.rb b/app_bravo/db/migrate/20260410120000_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..7718eb0
--- /dev/null
+++ b/app_bravo/db/migrate/20260410120000_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_at, :datetime
+    add_column :requests, :proposal_reason, :text
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..0acee28 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -101,6 +101,8 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_reason"
+    t.datetime "proposed_at"
     t.integer "provider_id", null: false
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
diff --git a/app_bravo/spec/factories/requests.rb b/app_bravo/spec/factories/requests.rb
index 67c374a..4da97f3 100644
--- a/app_bravo/spec/factories/requests.rb
+++ b/app_bravo/spec/factories/requests.rb
@@ -21,5 +21,11 @@
       state { "expired" }
       expired_at { Time.current }
     end
+
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_at { 5.days.from_now }
+      proposal_reason { "I'm unavailable at that time, how about this instead?" }
+    end
   end
 end
diff --git a/app_bravo/spec/models/request_spec.rb b/app_bravo/spec/models/request_spec.rb
index dec4a53..03e5e64 100644
--- a/app_bravo/spec/models/request_spec.rb
+++ b/app_bravo/spec/models/request_spec.rb
@@ -65,6 +65,64 @@
       end
     end
 
+    describe "counter_propose event" do
+      it "transitions from pending to counter_proposed" do
+        request.update!(proposed_at: 5.days.from_now, proposal_reason: "Better time")
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
+    describe "accept_proposal event" do
+      let(:proposed_time) { 5.days.from_now }
+      let(:counter_proposed_request) { create(:request, :counter_proposed, proposed_at: proposed_time) }
+
+      it "transitions from counter_proposed to accepted" do
+        counter_proposed_request.accept_proposal!
+        expect(counter_proposed_request).to be_accepted
+      end
+
+      it "updates scheduled_at to the proposed time" do
+        counter_proposed_request.accept_proposal!
+        expect(counter_proposed_request.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "sets accepted_at timestamp" do
+        freeze_time do
+          counter_proposed_request.accept_proposal!
+          expect(counter_proposed_request.reload.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "cannot accept proposal from pending" do
+        expect { request.accept_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_proposal event" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to pending" do
+        counter_proposed_request.decline_proposal!
+        expect(counter_proposed_request).to be_pending
+      end
+
+      it "clears proposal fields" do
+        counter_proposed_request.decline_proposal!
+        expect(counter_proposed_request.reload.proposed_at).to be_nil
+        expect(counter_proposed_request.reload.proposal_reason).to be_nil
+      end
+
+      it "cannot decline proposal from pending" do
+        expect { request.decline_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
     describe "expire event" do
       it "transitions from pending to expired" do
         request.expire!
diff --git a/app_bravo/spec/services/requests/accept_proposal_service_spec.rb b/app_bravo/spec/services/requests/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..082d5e7
--- /dev/null
+++ b/app_bravo/spec/services/requests/accept_proposal_service_spec.rb
@@ -0,0 +1,64 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposalService do
+  let(:provider) { create(:provider) }
+  let(:client) { create(:client) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider, proposed_at: proposed_time) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the proposal" do
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
+      it "sets accepted_at timestamp" do
+        freeze_time do
+          described_class.new(request: request, client: client).call
+          expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "creates an order linked to the request" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+        order = request.reload.order
+        expect(order).to be_present
+        expect(order.client).to eq(client)
+        expect(order.provider).to eq(provider)
+        expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+        expect(read_notification_log).to include("event=proposal_accepted")
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
+    context "when request is pending (not counter-proposed)" do
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
index 0000000..44d2ba2
--- /dev/null
+++ b/app_bravo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,60 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_at) { 5.days.from_now }
+  let(:reason) { "I'm busy at that time, how about this instead?" }
+
+  describe "#call" do
+    context "with valid params" do
+      it "counter-proposes the request" do
+        result = described_class.new(request: request, provider: provider, proposed_at: proposed_at, reason: reason).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_at).to be_within(1.second).of(proposed_at)
+        expect(request.proposal_reason).to eq(reason)
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, proposed_at: proposed_at, reason: reason).call
+        expect(read_notification_log).to include("event=request_counter_proposed")
+      end
+    end
+
+    context "with wrong provider" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: other_provider, proposed_at: proposed_at, reason: reason).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "without proposed_at" do
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_at: nil, reason: reason).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
+      end
+    end
+
+    context "without reason" do
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_at: proposed_at, reason: nil).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Reason is required")
+      end
+    end
+
+    context "when already accepted" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_at: proposed_at, reason: reason).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_bravo/spec/services/requests/decline_proposal_service_spec.rb b/app_bravo/spec/services/requests/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..75df82c
--- /dev/null
+++ b/app_bravo/spec/services/requests/decline_proposal_service_spec.rb
@@ -0,0 +1,47 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposalService do
+  let(:provider) { create(:provider) }
+  let(:client) { create(:client) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "declines the proposal and returns to pending" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears the proposal fields" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.proposed_at).to be_nil
+        expect(request.reload.proposal_reason).to be_nil
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+        expect(read_notification_log).to include("event=proposal_declined")
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
+    context "when request is pending (not counter-proposed)" do
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
