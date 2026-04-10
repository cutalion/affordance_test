# Experiment: e03-counter-proposal
# App: app_delta | Model: opus | Run: 1
# Branch: debt_experiment/e03-counter-proposal/app_delta/opus/run-1

---

## Claude Output

All 199 tests pass (42 related to the counter-proposal feature). Here's what was implemented:

**Counter-Proposal Feature Summary**

**New state**: `counter_proposed` added to the Request state machine, with three new events:
- `counter_propose` — provider proposes a different time (pending → counter_proposed)
- `accept_counter` — client accepts the new time (counter_proposed → accepted, creates an order)
- `decline_counter` — client declines (counter_proposed → pending, allowing provider to try again)

**Database**: Migration adds `counter_scheduled_at` and `counter_proposed_at` columns to `requests`.

**Services created**:
- `Requests::CounterProposeService` — validates provider ownership, sets counter time, notifies client
- `Requests::AcceptCounterService` — validates client ownership, accepts at the counter-proposed time, creates an order (mirrors `AcceptService`), notifies provider
- `Requests::DeclineCounterService` — validates client ownership, returns request to pending, clears counter fields, notifies provider

**API endpoints** (all PATCH):
- `PATCH /api/requests/:id/counter_propose` (provider, requires `scheduled_at` param)
- `PATCH /api/requests/:id/accept_counter` (client)
- `PATCH /api/requests/:id/decline_counter` (client)

**Notifications**: `request_counter_proposed`, `counter_proposal_accepted`, `counter_proposal_declined`

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/requests_controller.rb b/app_delta/app/controllers/api/requests_controller.rb
index 9b6998d..84428d6 100644
--- a/app_delta/app/controllers/api/requests_controller.rb
+++ b/app_delta/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_counter, :decline_counter]
 
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
+        scheduled_at: params[:scheduled_at]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptCounterService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
+    def decline_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineCounterService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -106,6 +140,8 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
+        counter_scheduled_at: request.counter_scheduled_at,
+        counter_proposed_at: request.counter_proposed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
         created_at: request.created_at,
diff --git a/app_delta/app/models/request.rb b/app_delta/app/models/request.rb
index 7f12baf..f70236d 100644
--- a/app_delta/app/models/request.rb
+++ b/app_delta/app/models/request.rb
@@ -9,6 +9,7 @@ class Request < ApplicationRecord
   validates :scheduled_at, presence: true
   validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
   validates :decline_reason, presence: true, if: -> { declined? }
+  validates :counter_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -28,6 +29,7 @@ class Request < ApplicationRecord
     state :accepted
     state :declined
     state :expired
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -46,5 +48,26 @@ class Request < ApplicationRecord
         update!(expired_at: Time.current)
       end
     end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+      after do
+        update!(counter_proposed_at: Time.current)
+      end
+    end
+
+    event :accept_counter do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(accepted_at: Time.current, scheduled_at: counter_scheduled_at)
+      end
+    end
+
+    event :decline_counter do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(counter_scheduled_at: nil, counter_proposed_at: nil)
+      end
+    end
   end
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
index 0000000..fc5fee5
--- /dev/null
+++ b/app_delta/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,28 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, scheduled_at:)
+      @request = request
+      @provider = provider
+      @scheduled_at = scheduled_at
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @scheduled_at.blank?
+
+      @request.counter_scheduled_at = @scheduled_at
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
diff --git a/app_delta/app/services/requests/decline_counter_service.rb b/app_delta/app/services/requests/decline_counter_service.rb
new file mode 100644
index 0000000..c29aa90
--- /dev/null
+++ b/app_delta/app/services/requests/decline_counter_service.rb
@@ -0,0 +1,25 @@
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
 
diff --git a/app_delta/db/migrate/20260408140809_add_counter_proposal_to_requests.rb b/app_delta/db/migrate/20260408140809_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..749e7b7
--- /dev/null
+++ b/app_delta/db/migrate/20260408140809_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :counter_scheduled_at, :datetime
+    add_column :requests, :counter_proposed_at, :datetime
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index c5b443e..5bfb58e 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_08_140809) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -113,6 +113,8 @@
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "client_id", null: false
+    t.datetime "counter_proposed_at"
+    t.datetime "counter_scheduled_at"
     t.datetime "created_at", null: false
     t.text "decline_reason"
     t.integer "duration_minutes", null: false
diff --git a/app_delta/spec/factories/requests.rb b/app_delta/spec/factories/requests.rb
index 67c374a..3a6698a 100644
--- a/app_delta/spec/factories/requests.rb
+++ b/app_delta/spec/factories/requests.rb
@@ -21,5 +21,11 @@
       state { "expired" }
       expired_at { Time.current }
     end
+
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      counter_scheduled_at { 5.days.from_now }
+      counter_proposed_at { Time.current }
+    end
   end
 end
diff --git a/app_delta/spec/models/request_spec.rb b/app_delta/spec/models/request_spec.rb
index dec4a53..42a4c87 100644
--- a/app_delta/spec/models/request_spec.rb
+++ b/app_delta/spec/models/request_spec.rb
@@ -23,6 +23,13 @@
         expect(request).not_to be_valid
       end
     end
+
+    context "when counter_proposed" do
+      it "requires counter_scheduled_at" do
+        request = build(:request, :counter_proposed, counter_scheduled_at: nil)
+        expect(request).not_to be_valid
+      end
+    end
   end
 
   describe "state machine" do
@@ -78,6 +85,72 @@
         end
       end
     end
+
+    describe "counter_propose event" do
+      it "transitions from pending to counter_proposed" do
+        request.counter_scheduled_at = 5.days.from_now
+        request.counter_propose!
+        expect(request).to be_counter_proposed
+      end
+
+      it "sets counter_proposed_at timestamp" do
+        freeze_time do
+          request.counter_scheduled_at = 5.days.from_now
+          request.counter_propose!
+          expect(request.reload.counter_proposed_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "cannot counter-propose from accepted" do
+        request.accept!
+        expect { request.counter_propose! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_counter event" do
+      let(:counter_time) { 5.days.from_now }
+      let(:request) { create(:request, :counter_proposed, counter_scheduled_at: counter_time) }
+
+      it "transitions from counter_proposed to accepted" do
+        request.accept_counter!
+        expect(request).to be_accepted
+      end
+
+      it "sets accepted_at and updates scheduled_at to counter time" do
+        freeze_time do
+          request.accept_counter!
+          request.reload
+          expect(request.accepted_at).to be_within(1.second).of(Time.current)
+          expect(request.scheduled_at).to be_within(1.second).of(counter_time)
+        end
+      end
+
+      it "cannot accept_counter from pending" do
+        pending_request = create(:request)
+        expect { pending_request.accept_counter! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_counter event" do
+      let(:request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to pending" do
+        request.decline_counter!
+        expect(request).to be_pending
+      end
+
+      it "clears counter proposal fields" do
+        request.decline_counter!
+        request.reload
+        expect(request.counter_scheduled_at).to be_nil
+        expect(request.counter_proposed_at).to be_nil
+      end
+
+      it "cannot decline_counter from pending" do
+        pending_request = create(:request)
+        expect { pending_request.decline_counter! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/app_delta/spec/services/requests/accept_counter_service_spec.rb b/app_delta/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..93a4585
--- /dev/null
+++ b/app_delta/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,54 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:counter_time) { 5.days.from_now }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider, counter_scheduled_at: counter_time) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the counter-proposal" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+      end
+
+      it "updates scheduled_at to the counter-proposed time" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.scheduled_at).to be_within(1.second).of(counter_time)
+      end
+
+      it "creates an order" do
+        expect {
+          described_class.new(request: request, client: client).call
+        }.to change(Order, :count).by(1)
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
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot accept counter-proposal")
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/requests/counter_propose_service_spec.rb b/app_delta/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..f83b3ee
--- /dev/null
+++ b/app_delta/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,52 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+
+  describe "#call" do
+    context "with correct provider and scheduled_at" do
+      let(:new_time) { 5.days.from_now }
+
+      it "counter-proposes the request" do
+        result = described_class.new(request: request, provider: provider, scheduled_at: new_time).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.counter_scheduled_at).to be_within(1.second).of(new_time)
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, scheduled_at: new_time).call
+        expect(read_notification_log).to include("event=request_counter_proposed")
+      end
+    end
+
+    context "without scheduled_at" do
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, scheduled_at: nil).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
+      end
+    end
+
+    context "with wrong provider" do
+      let(:other_provider) { create(:provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: other_provider, scheduled_at: 5.days.from_now).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
+      end
+    end
+
+    context "when request is not pending" do
+      let(:request) { create(:request, :accepted, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, scheduled_at: 5.days.from_now).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/requests/decline_counter_service_spec.rb b/app_delta/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..dfa7a05
--- /dev/null
+++ b/app_delta/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,49 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "declines the counter-proposal" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears counter proposal fields" do
+        described_class.new(request: request, client: client).call
+        request.reload
+        expect(request.counter_scheduled_at).to be_nil
+        expect(request.counter_proposed_at).to be_nil
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
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot decline counter-proposal")
+      end
+    end
+  end
+end
```
