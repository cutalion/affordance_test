# Experiment: e03-counter-proposal
# App: app_echo | Model: opus | Run: 2
# Branch: debt_experiment/e03-counter-proposal/app_echo/opus/run-2

---

## Claude Output

All done. Here's a summary of what was implemented:

**State machine** — Added `counter_proposed` state with 3 new events on `Request`:
- `counter_propose`: `pending` -> `counter_proposed`
- `accept_counter`: `counter_proposed` -> `accepted` (updates `scheduled_at` to proposed time)
- `decline_counter`: `counter_proposed` -> `pending` (clears proposal fields)

**3 new services:**
- `Requests::CounterProposeService` — provider proposes a different time + optional message
- `Requests::AcceptCounterService` — client accepts (creates payment, holds if card present, notifies provider)
- `Requests::DeclineCounterService` — client declines (returns to pending, clears proposal, notifies provider)

**API endpoints:**
- `PATCH /api/requests/:id/counter_propose` (provider, requires `proposed_scheduled_at`)
- `PATCH /api/requests/:id/accept_counter` (client)
- `PATCH /api/requests/:id/decline_counter` (client)

**JSON response** now includes `proposed_scheduled_at` and `counter_proposal_message` fields.

**21 new tests** covering happy paths, authorization checks, state guards, payment creation, and notifications. Full suite: 158 tests, 0 failures.

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..8b9f398 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :counter_propose, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -104,6 +104,45 @@ def reject
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
+        message: params[:message]
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
@@ -156,6 +195,8 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        counter_proposal_message: request.counter_proposal_message,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         started_at: request.started_at,
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..01cae67 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -38,6 +38,7 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -78,5 +79,20 @@ class Request < ApplicationRecord
     event :reject do
       transitions from: [:accepted, :in_progress], to: :rejected
     end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_counter do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(scheduled_at: proposed_scheduled_at, accepted_at: Time.current)
+      end
+    end
+
+    event :decline_counter do
+      transitions from: :counter_proposed, to: :pending
+    end
   end
 end
diff --git a/app_echo/app/services/requests/accept_counter_service.rb b/app_echo/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..e4fc76b
--- /dev/null
+++ b/app_echo/app/services/requests/accept_counter_service.rb
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
+      NotificationService.notify(@request.provider, :counter_proposal_accepted, request_id: @request.id)
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
diff --git a/app_echo/app/services/requests/counter_propose_service.rb b/app_echo/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..d6fc5fe
--- /dev/null
+++ b/app_echo/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,30 @@
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
+      @request.proposed_scheduled_at = @proposed_scheduled_at
+      @request.counter_proposal_message = @message
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
diff --git a/app_echo/app/services/requests/decline_counter_service.rb b/app_echo/app/services/requests/decline_counter_service.rb
new file mode 100644
index 0000000..d6093d5
--- /dev/null
+++ b/app_echo/app/services/requests/decline_counter_service.rb
@@ -0,0 +1,26 @@
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
+      @request.update!(proposed_scheduled_at: nil, counter_proposal_message: nil)
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
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index c2c99cb..c11cd94 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_084335) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_152727) do
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
     t.string "recurring_group_id"
     t.integer "recurring_index"
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
diff --git a/app_echo/spec/services/requests/accept_counter_service_spec.rb b/app_echo/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..6e5c823
--- /dev/null
+++ b/app_echo/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,83 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
+  let(:provider) { create(:provider) }
+  let(:client) { create(:client) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) do
+    create(:request,
+      client: client,
+      provider: provider,
+      state: "counter_proposed",
+      proposed_scheduled_at: proposed_time,
+      counter_proposal_message: "How about Thursday?"
+    )
+  end
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
+      it "creates a payment" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Payment, :count).by(1)
+
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
+
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
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot accept counter-proposal")
+      end
+    end
+  end
+end
diff --git a/app_echo/spec/services/requests/counter_propose_service_spec.rb b/app_echo/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..fdd6373
--- /dev/null
+++ b/app_echo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,100 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:client) { create(:client) }
+  let(:request) { create(:request, client: client, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and valid proposed time" do
+      it "transitions request to counter_proposed state" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "I'm busy that day, how about this time?"
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+      end
+
+      it "stores the proposed scheduled_at" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "Different time works better"
+        ).call
+
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "stores the counter-proposal message" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "How about Thursday?"
+        ).call
+
+        expect(request.reload.counter_proposal_message).to eq("How about Thursday?")
+      end
+
+      it "notifies the client" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "Different time"
+        ).call
+
+        expect(read_notification_log).to include("event=request_counter_proposed")
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
+    context "without proposed_scheduled_at" do
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
+    context "when request is not pending" do
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
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
diff --git a/app_echo/spec/services/requests/decline_counter_service_spec.rb b/app_echo/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..127e40e
--- /dev/null
+++ b/app_echo/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,66 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:provider) { create(:provider) }
+  let(:client) { create(:client) }
+  let(:request) do
+    create(:request,
+      client: client,
+      provider: provider,
+      state: "counter_proposed",
+      proposed_scheduled_at: 5.days.from_now,
+      counter_proposal_message: "How about Thursday?"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns request to pending state" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears the proposed_scheduled_at" do
+        described_class.new(request: request, client: client).call
+
+        expect(request.reload.proposed_scheduled_at).to be_nil
+      end
+
+      it "clears the counter_proposal_message" do
+        described_class.new(request: request, client: client).call
+
+        expect(request.reload.counter_proposal_message).to be_nil
+      end
+
+      it "notifies the provider" do
+        described_class.new(request: request, client: client).call
+
+        expect(read_notification_log).to include("event=counter_proposal_declined")
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
+    context "when request is not counter_proposed" do
+      let(:pending_request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client).call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot decline counter-proposal")
+      end
+    end
+  end
+end
```
