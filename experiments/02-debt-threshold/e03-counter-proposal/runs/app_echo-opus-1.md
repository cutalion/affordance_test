# Experiment: e03-counter-proposal
# App: app_echo | Model: opus | Run: 1
# Branch: debt_experiment/e03-counter-proposal/app_echo/opus/run-1

---

## Claude Output

All 7 tasks complete. Here's a summary of what was implemented:

## Counter-Proposal Feature — Complete

**3 commits on branch `debt_experiment/e03-counter-proposal/app_echo/opus/run-1`:**

1. **Migration** — Added `proposed_scheduled_at` (datetime) and `counter_proposal_message` (text) columns to `requests`

2. **Model + Services** — Added `counter_proposed` AASM state with three transitions:
   - `counter_propose`: pending → counter_proposed (provider proposes a new time)
   - `accept_counter`: counter_proposed → accepted (client accepts; updates `scheduled_at` to proposed time, creates payment)
   - `decline_counter`: counter_proposed → pending (client declines; clears proposal fields)
   - Also allows `cancel` from `counter_proposed` state

3. **Controller + Routes** — Three new API endpoints:
   - `PATCH /api/requests/:id/counter_propose` — provider sends `proposed_scheduled_at` and optional `message`
   - `PATCH /api/requests/:id/accept_counter` — client accepts the counter-proposal
   - `PATCH /api/requests/:id/decline_counter` — client declines the counter-proposal

**Test coverage:** 167 tests, 0 failures (21 new tests across 3 service specs + model spec additions).

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
index 7795b75..f13cc1e 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -15,6 +15,7 @@ class Request < ApplicationRecord
   validates :decline_reason, presence: true, if: -> { declined? }
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -38,6 +39,7 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -72,11 +74,29 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :accepted], to: :canceled
+      transitions from: [:pending, :accepted, :counter_proposed], to: :canceled
     end
 
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
+      after do
+        update!(proposed_scheduled_at: nil, counter_proposal_message: nil)
+      end
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
index 0000000..58a9b27
--- /dev/null
+++ b/app_echo/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,30 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_scheduled_at:, message:)
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
+      error("Cannot counter-propose request in #{@request.state} state")
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
index 0000000..c29aa90
--- /dev/null
+++ b/app_echo/app/services/requests/decline_counter_service.rb
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
diff --git a/app_echo/db/migrate/20260410072351_add_counter_proposal_to_requests.rb b/app_echo/db/migrate/20260410072351_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..5d67d2e
--- /dev/null
+++ b/app_echo/db/migrate/20260410072351_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :counter_proposal_message, :text
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..e4f72bc 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_072351) do
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
diff --git a/app_echo/docs/superpowers/plans/2026-04-10-counter-proposal.md b/app_echo/docs/superpowers/plans/2026-04-10-counter-proposal.md
new file mode 100644
index 0000000..d543a04
--- /dev/null
+++ b/app_echo/docs/superpowers/plans/2026-04-10-counter-proposal.md
@@ -0,0 +1,768 @@
+# Counter-Proposal Implementation Plan
+
+> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
+
+**Goal:** Allow providers to propose a different time for a booking request, which the client can accept or decline.
+
+**Architecture:** Extend the existing Request model with a `counter_proposed` AASM state. Add `proposed_scheduled_at` and `counter_proposal_message` columns. Create three new service objects (`CounterProposeService`, `AcceptCounterService`, `DeclineCounterService`) following the existing service pattern. Add three new controller actions and routes.
+
+**Tech Stack:** Rails 8.1, AASM, RSpec, FactoryBot
+
+---
+
+## File Structure
+
+- **Migration:** `db/migrate/YYYYMMDDHHMMSS_add_counter_proposal_to_requests.rb` — adds `proposed_scheduled_at` (datetime) and `counter_proposal_message` (text) columns
+- **Model:** `app/models/request.rb` — add `counter_proposed` state with transitions, add validation
+- **Service:** `app/services/requests/counter_propose_service.rb` — provider proposes a new time
+- **Service:** `app/services/requests/accept_counter_service.rb` — client accepts the counter-proposal
+- **Service:** `app/services/requests/decline_counter_service.rb` — client declines the counter-proposal
+- **Controller:** `app/controllers/api/requests_controller.rb` — add `counter_propose`, `accept_counter`, `decline_counter` actions
+- **Routes:** `config/routes.rb` — add three new member routes
+- **Tests:** `spec/models/request_spec.rb`, `spec/services/requests/counter_propose_service_spec.rb`, `spec/services/requests/accept_counter_service_spec.rb`, `spec/services/requests/decline_counter_service_spec.rb`
+- **Factory:** `spec/factories/requests.rb` — add `:counter_proposed` trait
+
+---
+
+### Task 1: Database Migration
+
+**Files:**
+- Create: `db/migrate/YYYYMMDDHHMMSS_add_counter_proposal_to_requests.rb`
+
+- [ ] **Step 1: Generate the migration**
+
+Run:
+```bash
+cd /home/cutalion/code/affordance_test/app_echo && bin/rails generate migration AddCounterProposalToRequests proposed_scheduled_at:datetime counter_proposal_message:text
+```
+
+- [ ] **Step 2: Run the migration**
+
+Run:
+```bash
+cd /home/cutalion/code/affordance_test/app_echo && bin/rails db:migrate
+```
+
+- [ ] **Step 3: Verify schema updated**
+
+Check `db/schema.rb` contains the new columns `proposed_scheduled_at` and `counter_proposal_message` in the `requests` table.
+
+- [ ] **Step 4: Commit**
+
+```bash
+git add db/migrate/*_add_counter_proposal_to_requests.rb db/schema.rb
+git commit -m "feat: add counter-proposal columns to requests table"
+```
+
+---
+
+### Task 2: Request Model — State Machine & Validation
+
+**Files:**
+- Modify: `app/models/request.rb`
+- Modify: `spec/models/request_spec.rb`
+- Modify: `spec/factories/requests.rb`
+
+- [ ] **Step 1: Write failing tests for the new state machine transitions**
+
+Add to `spec/models/request_spec.rb` inside the `"state machine"` describe block:
+
+```ruby
+describe "counter_propose event" do
+  it "transitions from pending to counter_proposed" do
+    request.update!(proposed_scheduled_at: 5.days.from_now)
+    request.counter_propose!
+    expect(request).to be_counter_proposed
+  end
+
+  it "cannot counter_propose from accepted" do
+    request.accept!
+    expect { request.counter_propose! }.to raise_error(AASM::InvalidTransition)
+  end
+end
+
+describe "accept_counter event" do
+  before do
+    request.update!(proposed_scheduled_at: 5.days.from_now)
+    request.counter_propose!
+  end
+
+  it "transitions from counter_proposed to accepted" do
+    request.accept_counter!
+    expect(request).to be_accepted
+  end
+
+  it "updates scheduled_at to proposed_scheduled_at" do
+    proposed_time = request.proposed_scheduled_at
+    request.accept_counter!
+    expect(request.reload.scheduled_at).to eq(proposed_time)
+  end
+
+  it "sets accepted_at timestamp" do
+    freeze_time do
+      request.accept_counter!
+      expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
+    end
+  end
+end
+
+describe "decline_counter event" do
+  before do
+    request.update!(proposed_scheduled_at: 5.days.from_now)
+    request.counter_propose!
+  end
+
+  it "transitions from counter_proposed to pending" do
+    request.decline_counter!
+    expect(request).to be_pending
+  end
+
+  it "clears proposed_scheduled_at" do
+    request.decline_counter!
+    expect(request.reload.proposed_scheduled_at).to be_nil
+  end
+
+  it "clears counter_proposal_message" do
+    request.update!(counter_proposal_message: "How about later?")
+    request.decline_counter!
+    expect(request.reload.counter_proposal_message).to be_nil
+  end
+end
+```
+
+Add to `spec/models/request_spec.rb` inside the `"validations"` describe block:
+
+```ruby
+context "when counter_proposed" do
+  it "requires proposed_scheduled_at" do
+    request = build(:request, :counter_proposed, proposed_scheduled_at: nil)
+    expect(request).not_to be_valid
+    expect(request.errors[:proposed_scheduled_at]).to be_present
+  end
+end
+```
+
+- [ ] **Step 2: Run tests to verify they fail**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/models/request_spec.rb`
+Expected: Multiple failures — `counter_propose`, `accept_counter`, `decline_counter` events not defined.
+
+- [ ] **Step 3: Add factory trait**
+
+Add to `spec/factories/requests.rb` after the `:rejected` trait:
+
+```ruby
+trait :counter_proposed do
+  state { "counter_proposed" }
+  proposed_scheduled_at { 5.days.from_now }
+  counter_proposal_message { "How about this time instead?" }
+end
+```
+
+- [ ] **Step 4: Implement the model changes**
+
+In `app/models/request.rb`, add the new state and events inside the `aasm` block. Add the state after `rejected`:
+
+```ruby
+state :counter_proposed
+```
+
+Add these events after the `reject` event:
+
+```ruby
+event :counter_propose do
+  transitions from: :pending, to: :counter_proposed
+end
+
+event :accept_counter do
+  transitions from: :counter_proposed, to: :accepted
+  after do
+    update!(scheduled_at: proposed_scheduled_at, accepted_at: Time.current)
+  end
+end
+
+event :decline_counter do
+  transitions from: :counter_proposed, to: :pending
+  after do
+    update!(proposed_scheduled_at: nil, counter_proposal_message: nil)
+  end
+end
+```
+
+Also allow cancel from `counter_proposed` — update the cancel event transitions:
+
+```ruby
+event :cancel do
+  transitions from: [:pending, :accepted, :counter_proposed], to: :canceled
+end
+```
+
+Add the validation after the `reject_reason` validation:
+
+```ruby
+validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
+```
+
+- [ ] **Step 5: Run tests to verify they pass**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/models/request_spec.rb`
+Expected: All tests pass.
+
+- [ ] **Step 6: Commit**
+
+```bash
+git add app/models/request.rb spec/models/request_spec.rb spec/factories/requests.rb
+git commit -m "feat: add counter_proposed state with transitions and validation"
+```
+
+---
+
+### Task 3: CounterProposeService
+
+**Files:**
+- Create: `app/services/requests/counter_propose_service.rb`
+- Create: `spec/services/requests/counter_propose_service_spec.rb`
+
+- [ ] **Step 1: Write the failing test**
+
+Create `spec/services/requests/counter_propose_service_spec.rb`:
+
+```ruby
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
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "This time works better for me"
+        ).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+      end
+
+      it "sets proposed_scheduled_at" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "sets counter_proposal_message" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "How about later?"
+        ).call
+        expect(request.reload.counter_proposal_message).to eq("How about later?")
+      end
+
+      it "notifies the client" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
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
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
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
+          proposed_scheduled_at: nil,
+          message: nil
+        ).call
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
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
+```
+
+- [ ] **Step 2: Run test to verify it fails**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/services/requests/counter_propose_service_spec.rb`
+Expected: FAIL — `uninitialized constant Requests::CounterProposeService`
+
+- [ ] **Step 3: Write the implementation**
+
+Create `app/services/requests/counter_propose_service.rb`:
+
+```ruby
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_scheduled_at:, message:)
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
+      error("Cannot counter-propose request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
+```
+
+- [ ] **Step 4: Run tests to verify they pass**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/services/requests/counter_propose_service_spec.rb`
+Expected: All pass.
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add app/services/requests/counter_propose_service.rb spec/services/requests/counter_propose_service_spec.rb
+git commit -m "feat: add CounterProposeService for provider counter-proposals"
+```
+
+---
+
+### Task 4: AcceptCounterService
+
+**Files:**
+- Create: `app/services/requests/accept_counter_service.rb`
+- Create: `spec/services/requests/accept_counter_service_spec.rb`
+
+- [ ] **Step 1: Write the failing test**
+
+Create `spec/services/requests/accept_counter_service_spec.rb`:
+
+```ruby
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
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
+        expect(request.reload.scheduled_at).to eq(proposed_time)
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
+        expect(request.reload.payment.fee_cents).to eq((request.amount_cents * 0.1).to_i)
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
+```
+
+- [ ] **Step 2: Run test to verify it fails**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/services/requests/accept_counter_service_spec.rb`
+Expected: FAIL — `uninitialized constant Requests::AcceptCounterService`
+
+- [ ] **Step 3: Write the implementation**
+
+Create `app/services/requests/accept_counter_service.rb`:
+
+```ruby
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
+```
+
+- [ ] **Step 4: Run tests to verify they pass**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/services/requests/accept_counter_service_spec.rb`
+Expected: All pass.
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add app/services/requests/accept_counter_service.rb spec/services/requests/accept_counter_service_spec.rb
+git commit -m "feat: add AcceptCounterService for client acceptance of counter-proposals"
+```
+
+---
+
+### Task 5: DeclineCounterService
+
+**Files:**
+- Create: `app/services/requests/decline_counter_service.rb`
+- Create: `spec/services/requests/decline_counter_service_spec.rb`
+
+- [ ] **Step 1: Write the failing test**
+
+Create `spec/services/requests/decline_counter_service_spec.rb`:
+
+```ruby
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request, :counter_proposed,
+      client: client,
+      provider: provider,
+      proposed_scheduled_at: 5.days.from_now,
+      counter_proposal_message: "How about later?"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns request to pending" do
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
+```
+
+- [ ] **Step 2: Run test to verify it fails**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/services/requests/decline_counter_service_spec.rb`
+Expected: FAIL — `uninitialized constant Requests::DeclineCounterService`
+
+- [ ] **Step 3: Write the implementation**
+
+Create `app/services/requests/decline_counter_service.rb`:
+
+```ruby
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
+```
+
+- [ ] **Step 4: Run tests to verify they pass**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec spec/services/requests/decline_counter_service_spec.rb`
+Expected: All pass.
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add app/services/requests/decline_counter_service.rb spec/services/requests/decline_counter_service_spec.rb
+git commit -m "feat: add DeclineCounterService for client declining counter-proposals"
+```
+
+---
+
+### Task 6: Controller Actions & Routes
+
+**Files:**
+- Modify: `config/routes.rb`
+- Modify: `app/controllers/api/requests_controller.rb`
+
+- [ ] **Step 1: Add routes**
+
+In `config/routes.rb`, inside the `member` block of `resources :requests`, add:
+
+```ruby
+patch :counter_propose
+patch :accept_counter
+patch :decline_counter
+```
+
+- [ ] **Step 2: Add controller actions**
+
+In `app/controllers/api/requests_controller.rb`:
+
+Update `before_action :set_request` to include the new actions:
+
+```ruby
+before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :counter_propose, :accept_counter, :decline_counter]
+```
+
+Add these actions after the `reject` action:
+
+```ruby
+def counter_propose
+  provider = current_provider!
+  return if performed?
+
+  if params[:proposed_scheduled_at].blank?
+    return render_unprocessable(["Proposed time is required"])
+  end
+
+  result = Requests::CounterProposeService.new(
+    request: @request,
+    provider: provider,
+    proposed_scheduled_at: params[:proposed_scheduled_at],
+    message: params[:message]
+  ).call
+  handle_service_result(result)
+end
+
+def accept_counter
+  client = current_client!
+  return if performed?
+
+  result = Requests::AcceptCounterService.new(
+    request: @request,
+    client: client
+  ).call
+  handle_service_result(result)
+end
+
+def decline_counter
+  client = current_client!
+  return if performed?
+
+  result = Requests::DeclineCounterService.new(
+    request: @request,
+    client: client
+  ).call
+  handle_service_result(result)
+end
+```
+
+Update `request_detail_json` to include the new fields. Add after `reject_reason`:
+
+```ruby
+proposed_scheduled_at: request.proposed_scheduled_at,
+counter_proposal_message: request.counter_proposal_message,
+```
+
+- [ ] **Step 3: Run the full test suite**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec`
+Expected: All tests pass.
+
+- [ ] **Step 4: Commit**
+
+```bash
+git add config/routes.rb app/controllers/api/requests_controller.rb
+git commit -m "feat: add counter-proposal controller actions and routes"
+```
+
+---
+
+### Task 7: Full Integration Verification
+
+- [ ] **Step 1: Run the full test suite**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bundle exec rspec`
+Expected: All tests pass, zero failures.
+
+- [ ] **Step 2: Verify routes**
+
+Run: `cd /home/cutalion/code/affordance_test/app_echo && bin/rails routes | grep counter`
+Expected output includes:
+```
+counter_propose_api_request PATCH /api/requests/:id/counter_propose(.:format) api/requests#counter_propose
+accept_counter_api_request  PATCH /api/requests/:id/accept_counter(.:format)  api/requests#accept_counter
+decline_counter_api_request PATCH /api/requests/:id/decline_counter(.:format) api/requests#decline_counter
+```
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
index a9aece5..c76c5fe 100644
--- a/app_echo/spec/models/request_spec.rb
+++ b/app_echo/spec/models/request_spec.rb
@@ -51,6 +51,14 @@
         expect(request.errors[:reject_reason]).to be_present
       end
     end
+
+    context "when counter_proposed" do
+      it "requires proposed_scheduled_at" do
+        request = build(:request, :counter_proposed, proposed_scheduled_at: nil)
+        expect(request).not_to be_valid
+        expect(request.errors[:proposed_scheduled_at]).to be_present
+      end
+    end
   end
 
   describe "state machine" do
@@ -180,6 +188,67 @@
         expect { request.reject! }.to raise_error(AASM::InvalidTransition)
       end
     end
+
+    describe "counter_propose event" do
+      it "transitions from pending to counter_proposed" do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
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
+    describe "accept_counter event" do
+      before do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.counter_propose!
+      end
+
+      it "transitions from counter_proposed to accepted" do
+        request.accept_counter!
+        expect(request).to be_accepted
+      end
+
+      it "updates scheduled_at to proposed_scheduled_at" do
+        proposed_time = request.proposed_scheduled_at
+        request.accept_counter!
+        expect(request.reload.scheduled_at).to eq(proposed_time)
+      end
+
+      it "sets accepted_at timestamp" do
+        freeze_time do
+          request.accept_counter!
+          expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+    end
+
+    describe "decline_counter event" do
+      before do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.counter_propose!
+      end
+
+      it "transitions from counter_proposed to pending" do
+        request.decline_counter!
+        expect(request).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        request.decline_counter!
+        expect(request.reload.proposed_scheduled_at).to be_nil
+      end
+
+      it "clears counter_proposal_message" do
+        request.update!(counter_proposal_message: "How about later?")
+        request.decline_counter!
+        expect(request.reload.counter_proposal_message).to be_nil
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/app_echo/spec/services/requests/accept_counter_service_spec.rb b/app_echo/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..fd52b91
--- /dev/null
+++ b/app_echo/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,76 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptCounterService do
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
+        expect(request.reload.payment.fee_cents).to eq((request.amount_cents * 0.1).to_i)
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
diff --git a/app_echo/spec/services/requests/counter_propose_service_spec.rb b/app_echo/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..1199204
--- /dev/null
+++ b/app_echo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,95 @@
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
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "This time works better for me"
+        ).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+      end
+
+      it "sets proposed_scheduled_at" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "sets counter_proposal_message" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "How about later?"
+        ).call
+        expect(request.reload.counter_proposal_message).to eq("How about later?")
+      end
+
+      it "notifies the client" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
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
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
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
+          proposed_scheduled_at: nil,
+          message: nil
+        ).call
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
+          proposed_scheduled_at: proposed_time,
+          message: nil
+        ).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
diff --git a/app_echo/spec/services/requests/decline_counter_service_spec.rb b/app_echo/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..5572e5e
--- /dev/null
+++ b/app_echo/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,59 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request, :counter_proposed,
+      client: client,
+      provider: provider,
+      proposed_scheduled_at: 5.days.from_now,
+      counter_proposal_message: "How about later?"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns request to pending" do
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
