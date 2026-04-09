# Experiment: e03-counter-proposal
# App: app_delta | Model: opus | Run: 2
# Branch: debt_experiment/e03-counter-proposal/app_delta/opus/run-2

---

## Claude Output

All 199 tests pass. Here's a summary of what was implemented:

**Counter-proposal feature for booking requests**

**New state flow:**
- `pending` → `counter_proposed` (provider proposes different time)
- `counter_proposed` → `accepted` (client accepts proposed time, order is created)
- `counter_proposed` → `declined` (client declines proposed time)
- `counter_proposed` → `expired` (request expires)

**Files changed:**
- **Migration** — added `proposed_scheduled_at` and `proposed_at` columns to `requests`
- **`Request` model** — added `counter_proposed` state, `counter_propose` and `accept_counter` events, extended `decline` and `expire` to work from `counter_proposed`, validation for `proposed_scheduled_at`
- **3 new services:**
  - `Requests::CounterProposeService` — provider proposes a new time
  - `Requests::AcceptCounterService` — client accepts (updates `scheduled_at`, creates order)
  - `Requests::DeclineCounterService` — client declines with a reason
- **Controller** — 3 new actions: `counter_propose`, `accept_counter`, `decline_counter`
- **Routes** — `PATCH /api/requests/:id/counter_propose`, `accept_counter`, `decline_counter`
- **Tests** — model specs for new states/transitions, service specs for all 3 services

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/requests_controller.rb b/app_delta/app/controllers/api/requests_controller.rb
index 9b6998d..043a7f8 100644
--- a/app_delta/app/controllers/api/requests_controller.rb
+++ b/app_delta/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -58,6 +58,46 @@ def decline
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
+      if params[:reason].blank?
+        return render_unprocessable(["Reason is required"])
+      end
+
+      result = Requests::DeclineCounterService.new(
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
+        proposed_at: request.proposed_at,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         client_id: request.client_id,
diff --git a/app_delta/app/models/request.rb b/app_delta/app/models/request.rb
index 7f12baf..ff559bd 100644
--- a/app_delta/app/models/request.rb
+++ b/app_delta/app/models/request.rb
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
@@ -37,11 +39,25 @@ class Request < ApplicationRecord
     end
 
     event :decline do
-      transitions from: :pending, to: :declined
+      transitions from: [:pending, :counter_proposed], to: :declined
+    end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+      after do
+        update!(proposed_at: Time.current)
+      end
+    end
+
+    event :accept_counter do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(scheduled_at: proposed_scheduled_at, accepted_at: Time.current)
+      end
     end
 
     event :expire do
-      transitions from: :pending, to: :expired
+      transitions from: [:pending, :counter_proposed], to: :expired
       after do
         update!(expired_at: Time.current)
       end
diff --git a/app_delta/app/services/requests/accept_counter_service.rb b/app_delta/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..1cbc7c5
--- /dev/null
+++ b/app_delta/app/services/requests/accept_counter_service.rb
@@ -0,0 +1,46 @@
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
+      Request.transaction do
+        @request.accept_counter!
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
diff --git a/app_delta/app/services/requests/counter_propose_service.rb b/app_delta/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..5549643
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
diff --git a/app_delta/app/services/requests/decline_counter_service.rb b/app_delta/app/services/requests/decline_counter_service.rb
new file mode 100644
index 0000000..27d78b6
--- /dev/null
+++ b/app_delta/app/services/requests/decline_counter_service.rb
@@ -0,0 +1,29 @@
+module Requests
+  class DeclineCounterService
+    def initialize(request:, client:, reason:)
+      @request = request
+      @client = client
+      @reason = reason
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("Request is not counter-proposed") unless @request.counter_proposed?
+      return error("Decline reason is required") if @reason.blank?
+
+      @request.decline_reason = @reason
+      @request.decline!
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
diff --git a/app_delta/config/routes.rb b/app_delta/config/routes.rb
index d9e099b..f23bdaa 100644
--- a/app_delta/config/routes.rb
+++ b/app_delta/config/routes.rb
@@ -14,6 +14,9 @@
       member do
         patch :accept
         patch :decline
+        patch :counter_propose
+        patch :accept_counter
+        patch :decline_counter
       end
     end
 
diff --git a/app_delta/db/migrate/20260409150000_add_counter_proposal_to_requests.rb b/app_delta/db/migrate/20260409150000_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..9b6c8dd
--- /dev/null
+++ b/app_delta/db/migrate/20260409150000_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime, if_not_exists: true
+    add_column :requests, :proposed_at, :datetime
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index 7580f62..67751b2 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_140800) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_150000) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -137,6 +137,8 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_at"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
diff --git a/app_delta/spec/factories/requests.rb b/app_delta/spec/factories/requests.rb
index 67c374a..57a1e9e 100644
--- a/app_delta/spec/factories/requests.rb
+++ b/app_delta/spec/factories/requests.rb
@@ -17,6 +17,12 @@
       decline_reason { "Not available" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      proposed_at { Time.current }
+    end
+
     trait :expired do
       state { "expired" }
       expired_at { Time.current }
diff --git a/app_delta/spec/models/request_spec.rb b/app_delta/spec/models/request_spec.rb
index dec4a53..e7f0c76 100644
--- a/app_delta/spec/models/request_spec.rb
+++ b/app_delta/spec/models/request_spec.rb
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
@@ -59,18 +66,72 @@
         expect(request).to be_declined
       end
 
+      it "transitions from counter_proposed to declined" do
+        counter_proposed = create(:request, :counter_proposed)
+        counter_proposed.decline_reason = "Changed my mind"
+        counter_proposed.decline!
+        expect(counter_proposed).to be_declined
+      end
+
       it "cannot decline from accepted" do
         request.accept!
         expect { request.decline! }.to raise_error(AASM::InvalidTransition)
       end
     end
 
+    describe "counter_propose event" do
+      it "transitions from pending to counter_proposed" do
+        request.proposed_scheduled_at = 5.days.from_now
+        request.counter_propose!
+        expect(request).to be_counter_proposed
+      end
+
+      it "sets proposed_at timestamp" do
+        freeze_time do
+          request.proposed_scheduled_at = 5.days.from_now
+          request.counter_propose!
+          expect(request.reload.proposed_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "cannot counter-propose from accepted" do
+        request.accept!
+        request.proposed_scheduled_at = 5.days.from_now
+        expect { request.counter_propose! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_counter event" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to accepted" do
+        counter_proposed_request.accept_counter!
+        expect(counter_proposed_request).to be_accepted
+      end
+
+      it "updates scheduled_at to proposed_scheduled_at" do
+        proposed_time = counter_proposed_request.proposed_scheduled_at
+        counter_proposed_request.accept_counter!
+        expect(counter_proposed_request.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "cannot accept counter from pending" do
+        expect { request.accept_counter! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
     describe "expire event" do
       it "transitions from pending to expired" do
         request.expire!
         expect(request).to be_expired
       end
 
+      it "transitions from counter_proposed to expired" do
+        counter_proposed = create(:request, :counter_proposed)
+        counter_proposed.expire!
+        expect(counter_proposed).to be_expired
+      end
+
       it "sets expired_at timestamp" do
         freeze_time do
           request.expire!
diff --git a/app_delta/spec/services/requests/accept_counter_service_spec.rb b/app_delta/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..042a043
--- /dev/null
+++ b/app_delta/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,55 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
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
+      it "creates an order linked to the request" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+        order = request.reload.order
+        expect(order).to be_present
+        expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
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
diff --git a/app_delta/spec/services/requests/counter_propose_service_spec.rb b/app_delta/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..1290418
--- /dev/null
+++ b/app_delta/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,57 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and proposed time" do
+      it "transitions to counter_proposed" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "sets proposed_at timestamp" do
+        freeze_time do
+          described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+          expect(request.reload.proposed_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(read_notification_log).to include("event=counter_proposal")
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
+    context "without proposed time" do
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
diff --git a/app_delta/spec/services/requests/decline_counter_service_spec.rb b/app_delta/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..ec3c160
--- /dev/null
+++ b/app_delta/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,50 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client and reason" do
+      it "declines the counter-proposal" do
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
+    context "when request is pending (not counter-proposed)" do
+      let(:pending_request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client, reason: "No").call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
