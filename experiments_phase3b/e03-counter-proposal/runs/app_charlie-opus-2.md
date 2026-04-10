# Experiment: e03-counter-proposal
# App: app_charlie | Model: opus | Run: 2
# Branch: debt_experiment/e03-counter-proposal/app_charlie/opus/run-2

---

## Claude Output

All done. Here's a summary of what was implemented:

**Counter-proposal feature** — providers can propose a different time for a booking, and clients can accept or decline.

### Changes made:

**Migration** — `db/migrate/20260410070412_add_counter_proposal_fields_to_requests.rb`
- Added `proposed_scheduled_at` (datetime) and `counter_propose_reason` (text) to `requests`

**Model** — `app/models/request.rb`
- New `counter_proposed` state
- `counter_propose` event: `pending` → `counter_proposed`
- `accept_counter` event: `counter_proposed` → `accepted` (updates `scheduled_at` to the proposed time, creates payment)
- `decline_counter` event: `counter_proposed` → `pending` (clears proposal fields)
- `cancel` also allowed from `counter_proposed` state

**Services:**
- `Requests::CounterProposeService` — provider proposes a new time with optional reason
- `Requests::AcceptCounterService` — client accepts (schedules at new time, creates payment + hold, like AcceptService)
- `Requests::DeclineCounterService` — client declines (returns to pending, clears proposal)

**API endpoints** (all PATCH):
- `PATCH /api/requests/:id/counter_propose` — provider action, requires `proposed_scheduled_at`, optional `reason`
- `PATCH /api/requests/:id/accept_counter` — client action
- `PATCH /api/requests/:id/decline_counter` — client action

**Tests** — 19 new specs covering all three services (happy paths, authorization, state guards, notifications, payment creation).

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..a10c638 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_counter, :decline_counter, :start, :complete, :cancel, :reject]
 
     def index
       requests = scoped_requests
@@ -58,6 +58,45 @@ def decline
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
+        proposed_scheduled_at: params[:proposed_scheduled_at],
+        reason: params[:reason]
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
     def start
       provider = current_provider!
       return if performed?
@@ -158,6 +197,8 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        counter_propose_reason: request.counter_propose_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         started_at: request.started_at,
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..59f5bee 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -37,6 +37,7 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -49,6 +50,27 @@ class Request < ApplicationRecord
       transitions from: :pending, to: :declined
     end
 
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_counter do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(
+          scheduled_at: proposed_scheduled_at,
+          accepted_at: Time.current
+        )
+      end
+    end
+
+    event :decline_counter do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil, counter_propose_reason: nil)
+      end
+    end
+
     event :expire do
       transitions from: :pending, to: :expired
       after do
@@ -71,7 +93,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :accepted], to: :canceled
+      transitions from: [:pending, :accepted, :counter_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/app_charlie/app/services/requests/accept_counter_service.rb b/app_charlie/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..0bcf031
--- /dev/null
+++ b/app_charlie/app/services/requests/accept_counter_service.rb
@@ -0,0 +1,41 @@
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
+        Payment.create!(
+          request: @request,
+          amount_cents: @request.amount_cents,
+          currency: @request.currency,
+          fee_cents: calculate_fee(@request.amount_cents),
+          status: "pending"
+        )
+      end
+
+      PaymentGateway.hold(@request.payment) if @client.default_card
+
+      NotificationService.notify(@request.provider, :counter_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter-proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_charlie/app/services/requests/counter_propose_service.rb b/app_charlie/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..7d3b320
--- /dev/null
+++ b/app_charlie/app/services/requests/counter_propose_service.rb
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
+      @request.counter_propose_reason = @reason
+      @request.counter_propose!
+
+      NotificationService.notify(@request.client, :counter_proposed, request_id: @request.id, proposed_scheduled_at: @proposed_scheduled_at)
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
diff --git a/app_charlie/app/services/requests/decline_counter_service.rb b/app_charlie/app/services/requests/decline_counter_service.rb
new file mode 100644
index 0000000..5027f8f
--- /dev/null
+++ b/app_charlie/app/services/requests/decline_counter_service.rb
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
+      NotificationService.notify(@request.provider, :counter_declined, request_id: @request.id)
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
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..3b0262b 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -14,6 +14,9 @@
       member do
         patch :accept
         patch :decline
+        patch :counter_propose
+        patch :accept_counter
+        patch :decline_counter
         patch :start
         patch :complete
         patch :cancel
diff --git a/app_charlie/db/migrate/20260410070412_add_counter_proposal_fields_to_requests.rb b/app_charlie/db/migrate/20260410070412_add_counter_proposal_fields_to_requests.rb
new file mode 100644
index 0000000..1194329
--- /dev/null
+++ b/app_charlie/db/migrate/20260410070412_add_counter_proposal_fields_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalFieldsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :counter_propose_reason, :text
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..bea0d56 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140805) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_070412) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -74,6 +74,7 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.text "counter_propose_reason"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.text "decline_reason"
@@ -81,6 +82,7 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/app_charlie/spec/factories/requests.rb b/app_charlie/spec/factories/requests.rb
index dad8264..d6bd2f8 100644
--- a/app_charlie/spec/factories/requests.rb
+++ b/app_charlie/spec/factories/requests.rb
@@ -47,6 +47,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      counter_propose_reason { "I'm available later" }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_charlie/spec/services/requests/accept_counter_service_spec.rb b/app_charlie/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..2801750
--- /dev/null
+++ b/app_charlie/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,71 @@
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
+      it "creates a payment for the request" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Payment, :count).by(1)
+        payment = request.reload.payment
+        expect(payment).to be_present
+        expect(payment.amount_cents).to eq(request.amount_cents)
+        expect(payment.status).to eq("pending")
+      end
+
+      it "calculates fee as 10% of amount" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.payment.fee_cents).to eq(35_000)
+      end
+
+      context "when client has a default card" do
+        let!(:card) { create(:card, :default, client: client) }
+
+        it "holds the payment" do
+          described_class.new(request: request, client: client).call
+          expect(request.reload.payment.status).to eq("held")
+        end
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+        expect(read_notification_log).to include("event=counter_accepted")
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
diff --git a/app_charlie/spec/services/requests/counter_propose_service_spec.rb b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..211cdbc
--- /dev/null
+++ b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
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
+      it "counter-proposes the request" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "stores the reason when provided" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time, reason: "I'm available later").call
+        expect(result[:success]).to be true
+        expect(request.reload.counter_propose_reason).to eq("I'm available later")
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(read_notification_log).to include("event=counter_proposed")
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
+    context "when request is not pending" do
+      let(:request) { create(:request, :accepted, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/decline_counter_service_spec.rb b/app_charlie/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..abcc2b9
--- /dev/null
+++ b/app_charlie/spec/services/requests/decline_counter_service_spec.rb
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
+      it "declines the counter-proposal and returns to pending" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears the proposed fields" do
+        described_class.new(request: request, client: client).call
+        request.reload
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.counter_propose_reason).to be_nil
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+        expect(read_notification_log).to include("event=counter_declined")
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
