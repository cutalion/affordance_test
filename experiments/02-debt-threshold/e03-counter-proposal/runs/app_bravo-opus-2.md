# Experiment: e03-counter-proposal
# App: app_bravo | Model: opus | Run: 2
# Branch: debt_experiment/e03-counter-proposal/app_bravo/opus/run-2

---

## Claude Output

All 151 tests pass. Here's a summary of what was implemented:

## Counter-Proposal Feature

**New state machine flow:**
```
pending → counter_proposed (provider proposes new time)
counter_proposed → accepted (client accepts → order created)
counter_proposed → pending (client declines → can try again)
```

**Changes made:**

| File | Change |
|------|--------|
| `db/migrate/..._add_proposed_scheduled_at_to_requests.rb` | Adds `proposed_scheduled_at` column |
| `app/models/request.rb` | New `counter_proposed` state, 3 new events, validation |
| `app/services/requests/counter_propose_service.rb` | Provider proposes a different time |
| `app/services/requests/accept_counter_proposal_service.rb` | Client accepts (updates scheduled_at, creates order) |
| `app/services/requests/decline_counter_proposal_service.rb` | Client declines (returns to pending) |
| `app/controllers/api/requests_controller.rb` | 3 new actions + `proposed_scheduled_at` in JSON |
| `config/routes.rb` | 3 new member routes |

**API endpoints:**
- `PATCH /api/requests/:id/counter_propose` — provider sends `proposed_scheduled_at`
- `PATCH /api/requests/:id/accept_counter_proposal` — client accepts
- `PATCH /api/requests/:id/decline_counter_proposal` — client declines (request returns to `pending` so provider can accept, decline, or counter-propose again)

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/requests_controller.rb b/app_bravo/app/controllers/api/requests_controller.rb
index 9b6998d..8cb2857 100644
--- a/app_bravo/app/controllers/api/requests_controller.rb
+++ b/app_bravo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_counter_proposal, :decline_counter_proposal]
 
     def index
       requests = scoped_requests
@@ -58,6 +58,40 @@ def decline
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
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -104,6 +138,7 @@ def request_detail_json(request)
         location: request.location,
         notes: request.notes,
         decline_reason: request.decline_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         client_id: request.client_id,
diff --git a/app_bravo/app/models/request.rb b/app_bravo/app/models/request.rb
index 7f12baf..01f550e 100644
--- a/app_bravo/app/models/request.rb
+++ b/app_bravo/app/models/request.rb
@@ -9,6 +9,7 @@ class Request < ApplicationRecord
   validates :scheduled_at, presence: true
   validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
   validates :decline_reason, presence: true, if: -> { declined? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -28,6 +29,7 @@ class Request < ApplicationRecord
     state :accepted
     state :declined
     state :expired
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -46,5 +48,23 @@ class Request < ApplicationRecord
         update!(expired_at: Time.current)
       end
     end
+
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
+        update!(proposed_scheduled_at: nil)
+      end
+    end
   end
 end
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
index 0000000..5560162
--- /dev/null
+++ b/app_bravo/app/services/requests/counter_propose_service.rb
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
 
diff --git a/app_bravo/db/migrate/20260410065054_add_proposed_scheduled_at_to_requests.rb b/app_bravo/db/migrate/20260410065054_add_proposed_scheduled_at_to_requests.rb
new file mode 100644
index 0000000..a95e8f4
--- /dev/null
+++ b/app_bravo/db/migrate/20260410065054_add_proposed_scheduled_at_to_requests.rb
@@ -0,0 +1,5 @@
+class AddProposedScheduledAtToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..18b3d9f 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_065054) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -101,6 +101,7 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
diff --git a/app_bravo/spec/factories/requests.rb b/app_bravo/spec/factories/requests.rb
index 67c374a..0a51e7c 100644
--- a/app_bravo/spec/factories/requests.rb
+++ b/app_bravo/spec/factories/requests.rb
@@ -17,6 +17,11 @@
       decline_reason { "Not available" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :expired do
       state { "expired" }
       expired_at { Time.current }
diff --git a/app_bravo/spec/models/request_spec.rb b/app_bravo/spec/models/request_spec.rb
index dec4a53..298f05c 100644
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
@@ -78,6 +85,65 @@
         end
       end
     end
+
+    describe "counter_propose event" do
+      it "transitions from pending to counter_proposed" do
+        request.proposed_scheduled_at = 5.days.from_now
+        request.counter_propose!
+        expect(request).to be_counter_proposed
+      end
+
+      it "cannot counter_propose from accepted" do
+        request.accept!
+        expect { request.counter_propose! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_counter_proposal event" do
+      let(:request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to accepted" do
+        request.accept_counter_proposal!
+        expect(request).to be_accepted
+      end
+
+      it "updates scheduled_at to proposed_scheduled_at" do
+        proposed_time = request.proposed_scheduled_at
+        request.accept_counter_proposal!
+        expect(request.reload.scheduled_at).to eq(proposed_time)
+      end
+
+      it "sets accepted_at timestamp" do
+        freeze_time do
+          request.accept_counter_proposal!
+          expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "cannot accept_counter_proposal from pending" do
+        pending_request = create(:request)
+        expect { pending_request.accept_counter_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_counter_proposal event" do
+      let(:request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed back to pending" do
+        request.decline_counter_proposal!
+        expect(request).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        request.decline_counter_proposal!
+        expect(request.reload.proposed_scheduled_at).to be_nil
+      end
+
+      it "cannot decline_counter_proposal from pending" do
+        pending_request = create(:request)
+        expect { pending_request.decline_counter_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..5a36005
--- /dev/null
+++ b/app_bravo/spec/services/requests/accept_counter_proposal_service_spec.rb
@@ -0,0 +1,55 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
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
+        proposed_time = request.proposed_scheduled_at
+        described_class.new(request: request, client: client).call
+        expect(request.reload.scheduled_at).to eq(proposed_time)
+      end
+
+      it "creates an order linked to the request" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+        order = request.reload.order
+        expect(order).to be_present
+        expect(order.scheduled_at).to eq(request.scheduled_at)
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
+    context "when request is pending (not counter_proposed)" do
+      let(:pending_request) { create(:request, client: client) }
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
index 0000000..ec6af72
--- /dev/null
+++ b/app_bravo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,54 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and valid proposed time" do
+      it "transitions request to counter_proposed" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+      end
+
+      it "stores the proposed_scheduled_at" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(read_notification_log).to include("event=request_counter_proposed")
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
+    context "without proposed_scheduled_at" do
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: nil).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
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
diff --git a/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..b7e927c
--- /dev/null
+++ b/app_bravo/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,46 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns the request to pending" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.proposed_scheduled_at).to be_nil
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
+    context "when request is pending (not counter_proposed)" do
+      let(:pending_request) { create(:request, client: client) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
