# Experiment: e03-counter-proposal
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e03-counter-proposal/app_echo/opus/run-3

---

## Claude Output

All 168 tests pass (0 failures). Here's a summary of what was implemented:

## Counter-Proposal Feature

**Flow**: A provider can propose a different time for a pending booking. The client can then accept (booking proceeds with the new time) or decline (request reverts to pending).

### Changes made:

**Migration** (`db/migrate/20260410120000_add_counter_proposal_to_requests.rb`)
- Adds `proposed_scheduled_at` (datetime) and `counter_proposal_message` (text) to `requests`

**Model** (`app/models/request.rb`)
- New `counter_proposed` state
- `counter_propose` event: `pending` → `counter_proposed`
- `revert_to_pending` event: `counter_proposed` → `pending` (clears proposal fields)
- `accept`/`decline`/`cancel` now also transition from `counter_proposed`
- Validates `proposed_scheduled_at` presence when `counter_proposed`

**Services**:
- `Requests::CounterProposeService` — provider proposes a new time with optional message; validates ownership, time presence, and future date; notifies client
- `Requests::AcceptCounterProposalService` — client accepts; updates `scheduled_at` to proposed time, creates payment, holds if card exists; notifies provider
- `Requests::DeclineCounterProposalService` — client declines; reverts to pending, clears proposal fields; notifies provider

**Routes**: `PATCH /api/requests/:id/counter_propose`, `accept_counter`, `decline_counter`

**API response** now includes `proposed_scheduled_at` and `counter_proposal_message`

**Tests**: 29 new specs covering all services, model validations, and state transitions.

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..3503f87 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :counter_propose, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -104,6 +104,41 @@ def reject
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
+        message: params[:message]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter
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
+    def decline_counter
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
@@ -156,6 +191,8 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        counter_proposal_message: request.counter_proposal_message,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         started_at: request.started_at,
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..7f8facf 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -15,6 +15,7 @@ class Request < ApplicationRecord
   validates :decline_reason, presence: true, if: -> { declined? }
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -38,16 +39,17 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
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
@@ -71,8 +73,19 @@ class Request < ApplicationRecord
       end
     end
 
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :revert_to_pending do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil, counter_proposal_message: nil)
+      end
+    end
+
     event :cancel do
-      transitions from: [:pending, :accepted], to: :canceled
+      transitions from: [:pending, :accepted, :counter_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/app_echo/app/services/requests/accept_counter_proposal_service.rb b/app_echo/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..7c58db5
--- /dev/null
+++ b/app_echo/app/services/requests/accept_counter_proposal_service.rb
@@ -0,0 +1,43 @@
+module Requests
+  class AcceptCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("No counter-proposal to accept") unless @request.counter_proposed?
+
+      Request.transaction do
+        @request.scheduled_at = @request.proposed_scheduled_at
+        @request.accept!
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
+      NotificationService.notify(@request.provider, :counter_proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter-proposal in #{@request.state} state")
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
diff --git a/app_echo/app/services/requests/counter_propose_service.rb b/app_echo/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..696a564
--- /dev/null
+++ b/app_echo/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,37 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_scheduled_at:, message: nil)
+      @request = request
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+      @message = message
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      parsed_time = parse_time(@proposed_scheduled_at)
+      return error("Proposed time must be in the future") if parsed_time <= Time.current
+
+      @request.proposed_scheduled_at = parsed_time
+      @request.counter_proposal_message = @message
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
+    def parse_time(value)
+      value.is_a?(String) ? Time.zone.parse(value) : value
+    end
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/app_echo/app/services/requests/decline_counter_proposal_service.rb b/app_echo/app/services/requests/decline_counter_proposal_service.rb
new file mode 100644
index 0000000..a62e8d0
--- /dev/null
+++ b/app_echo/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,26 @@
+module Requests
+  class DeclineCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("No counter-proposal to decline") unless @request.counter_proposed?
+
+      @request.revert_to_pending!
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
diff --git a/app_echo/config/routes.rb b/app_echo/config/routes.rb
index da43a53..a93a62e 100644
--- a/app_echo/config/routes.rb
+++ b/app_echo/config/routes.rb
@@ -18,6 +18,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :counter_propose
+        patch :accept_counter
+        patch :decline_counter
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/app_echo/db/migrate/20260410120000_add_counter_proposal_to_requests.rb b/app_echo/db/migrate/20260410120000_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..5d67d2e
--- /dev/null
+++ b/app_echo/db/migrate/20260410120000_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :counter_proposal_message, :text
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..36609c3 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -93,6 +93,7 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.text "counter_proposal_message"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.text "decline_reason"
@@ -101,6 +102,7 @@
     t.string "location"
     t.text "notes"
     t.integer "proposed_amount_cents"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.text "response_message"
diff --git a/app_echo/spec/factories/requests.rb b/app_echo/spec/factories/requests.rb
index 4620d0c..0666ef1 100644
--- a/app_echo/spec/factories/requests.rb
+++ b/app_echo/spec/factories/requests.rb
@@ -47,6 +47,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      counter_proposal_message { "How about this time instead?" }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_echo/spec/models/request_spec.rb b/app_echo/spec/models/request_spec.rb
index a9aece5..6520cfe 100644
--- a/app_echo/spec/models/request_spec.rb
+++ b/app_echo/spec/models/request_spec.rb
@@ -44,6 +44,14 @@
       end
     end
 
+    context "when counter_proposed" do
+      it "requires proposed_scheduled_at" do
+        request = build(:request, :counter_proposed, proposed_scheduled_at: nil)
+        expect(request).not_to be_valid
+        expect(request.errors[:proposed_scheduled_at]).to be_present
+      end
+    end
+
     context "when rejected" do
       it "requires reject_reason" do
         request = build(:request, :rejected, reject_reason: nil)
@@ -160,6 +168,67 @@
       end
     end
 
+    describe "counter_propose event" do
+      it "transitions from pending to counter_proposed" do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
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
+    describe "revert_to_pending event" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to pending" do
+        counter_proposed_request.revert_to_pending!
+        expect(counter_proposed_request).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        counter_proposed_request.revert_to_pending!
+        expect(counter_proposed_request.reload.proposed_scheduled_at).to be_nil
+      end
+
+      it "clears counter_proposal_message" do
+        counter_proposed_request.revert_to_pending!
+        expect(counter_proposed_request.reload.counter_proposal_message).to be_nil
+      end
+    end
+
+    describe "accept from counter_proposed" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to accepted" do
+        counter_proposed_request.accept!
+        expect(counter_proposed_request).to be_accepted
+      end
+    end
+
+    describe "decline from counter_proposed" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to declined" do
+        counter_proposed_request.update!(decline_reason: "Not interested")
+        counter_proposed_request.decline!
+        expect(counter_proposed_request).to be_declined
+      end
+    end
+
+    describe "cancel from counter_proposed" do
+      let(:counter_proposed_request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to canceled" do
+        counter_proposed_request.update!(cancel_reason: "Changed my mind")
+        counter_proposed_request.cancel!
+        expect(counter_proposed_request).to be_canceled
+      end
+    end
+
     describe "reject event" do
       it "transitions from accepted to rejected" do
         request.accept!
diff --git a/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..c71a328
--- /dev/null
+++ b/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb
@@ -0,0 +1,76 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) do
+    create(:request, :counter_proposed,
+      client: client,
+      provider: provider,
+      proposed_scheduled_at: proposed_time
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the request" do
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
+      it "creates a payment" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Payment, :count).by(1)
+        payment = request.reload.payment
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
+        expect(result[:error]).to include("No counter-proposal to accept")
+      end
+    end
+  end
+end
diff --git a/app_echo/spec/services/requests/counter_propose_service_spec.rb b/app_echo/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..bf49085
--- /dev/null
+++ b/app_echo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,101 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and valid proposed time" do
+      it "transitions to counter_proposed" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+      end
+
+      it "sets proposed_scheduled_at" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "sets counter_proposal_message when provided" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "I'm available later that week"
+        ).call
+        expect(request.reload.counter_proposal_message).to eq("I'm available later that week")
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
+    context "with proposed time in the past" do
+      it "returns error" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: 1.day.ago
+        ).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time must be in the future")
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
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
diff --git a/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..4686307
--- /dev/null
+++ b/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,59 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request, :counter_proposed,
+      client: client,
+      provider: provider,
+      proposed_scheduled_at: 5.days.from_now,
+      counter_proposal_message: "How about next week?"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "reverts the request to pending" do
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
+      it "clears counter_proposal_message" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.counter_proposal_message).to be_nil
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
+        expect(result[:error]).to include("No counter-proposal to decline")
+      end
+    end
+  end
+end
```
