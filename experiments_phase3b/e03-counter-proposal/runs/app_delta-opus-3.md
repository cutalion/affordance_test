# Experiment: e03-counter-proposal
# App: app_delta | Model: opus | Run: 3
# Branch: debt_experiment/e03-counter-proposal/app_delta/opus/run-3

---

## Claude Output

All tasks complete. Here's a summary of what was implemented:

## Counter-Proposal Feature — Complete

**New flow:** Client creates request (pending) → Provider can now `counter_propose` with a different time → Client can `accept_proposal` (creates order at new time) or `decline_proposal` (returns to pending).

**What was added:**

| Layer | Files |
|-------|-------|
| Migration | `db/migrate/20260409200000_add_counter_proposal_to_requests.rb` — `proposed_scheduled_at`, `proposal_reason` columns |
| Model | `app/models/request.rb` — `counter_proposed` state, 3 new AASM events, validation |
| Services | `counter_propose_service.rb`, `accept_proposal_service.rb`, `decline_proposal_service.rb` |
| Controller | 3 new actions in `api/requests_controller.rb` + JSON serialization updated |
| Routes | `PATCH /api/requests/:id/counter_propose`, `accept_proposal`, `decline_proposal` |
| Tests | 15 new specs across model + 3 service specs, **194 total, 0 failures** |

Would you like me to commit these changes?

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/requests_controller.rb b/app_delta/app/controllers/api/requests_controller.rb
index 9b6998d..c993ea3 100644
--- a/app_delta/app/controllers/api/requests_controller.rb
+++ b/app_delta/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_proposal, :decline_proposal]
 
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
@@ -104,6 +143,8 @@ def request_detail_json(request)
         location: request.location,
         notes: request.notes,
         decline_reason: request.decline_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        proposal_reason: request.proposal_reason,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         client_id: request.client_id,
diff --git a/app_delta/app/models/request.rb b/app_delta/app/models/request.rb
index 7f12baf..38f3d1f 100644
--- a/app_delta/app/models/request.rb
+++ b/app_delta/app/models/request.rb
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
+    event :accept_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(accepted_at: Time.current)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil, proposal_reason: nil)
+      end
+    end
   end
 end
diff --git a/app_delta/app/services/requests/accept_proposal_service.rb b/app_delta/app/services/requests/accept_proposal_service.rb
new file mode 100644
index 0000000..b4006a7
--- /dev/null
+++ b/app_delta/app/services/requests/accept_proposal_service.rb
@@ -0,0 +1,47 @@
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
+        @request.scheduled_at = @request.proposed_scheduled_at
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
diff --git a/app_delta/app/services/requests/counter_propose_service.rb b/app_delta/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..081e2d5
--- /dev/null
+++ b/app_delta/app/services/requests/counter_propose_service.rb
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
diff --git a/app_delta/app/services/requests/decline_proposal_service.rb b/app_delta/app/services/requests/decline_proposal_service.rb
new file mode 100644
index 0000000..71260ea
--- /dev/null
+++ b/app_delta/app/services/requests/decline_proposal_service.rb
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
diff --git a/app_delta/config/routes.rb b/app_delta/config/routes.rb
index d9e099b..00e77c5 100644
--- a/app_delta/config/routes.rb
+++ b/app_delta/config/routes.rb
@@ -14,6 +14,9 @@
       member do
         patch :accept
         patch :decline
+        patch :counter_propose
+        patch :accept_proposal
+        patch :decline_proposal
       end
     end
 
diff --git a/app_delta/db/migrate/20260409200000_add_counter_proposal_to_requests.rb b/app_delta/db/migrate/20260409200000_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..77add79
--- /dev/null
+++ b/app_delta/db/migrate/20260409200000_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime unless column_exists?(:requests, :proposed_scheduled_at)
+    add_column :requests, :proposal_reason, :text unless column_exists?(:requests, :proposal_reason)
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index 7580f62..2ee7167 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_140800) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_200000) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -137,6 +137,9 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_reason"
+    t.datetime "proposed_at"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
diff --git a/app_delta/docs/superpowers/plans/2026-04-09-counter-proposal.md b/app_delta/docs/superpowers/plans/2026-04-09-counter-proposal.md
new file mode 100644
index 0000000..7df44b7
--- /dev/null
+++ b/app_delta/docs/superpowers/plans/2026-04-09-counter-proposal.md
@@ -0,0 +1,756 @@
+# Counter-Proposal for Booking Requests — Implementation Plan
+
+> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
+
+**Goal:** Allow providers to propose a different time for a booking request, and let clients accept or decline that proposal.
+
+**Architecture:** Add a `counter_proposed` state to the Request AASM state machine. Providers call `counter_propose` (from `pending`) with a proposed time and optional reason. Clients call `accept_proposal` (transitions to `accepted`, updates `scheduled_at`, creates order) or `decline_proposal` (returns to `pending`). Three new service objects follow the existing pattern. Two new columns on `requests`: `proposed_scheduled_at` and `proposal_reason`.
+
+**Tech Stack:** Rails 8.1, AASM, RSpec, FactoryBot, Shoulda Matchers
+
+---
+
+### Task 1: Migration — Add counter-proposal columns to requests
+
+**Files:**
+- Create: `db/migrate/20260409200000_add_counter_proposal_to_requests.rb`
+- Modify: `db/schema.rb` (auto-generated by migration)
+
+- [ ] **Step 1: Create the migration**
+
+```ruby
+# db/migrate/20260409200000_add_counter_proposal_to_requests.rb
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :proposal_reason, :text
+  end
+end
+```
+
+- [ ] **Step 2: Run the migration**
+
+Run: `bin/rails db:migrate`
+Expected: schema.rb updated with `proposed_scheduled_at` and `proposal_reason` columns in the `requests` table.
+
+- [ ] **Step 3: Commit**
+
+```bash
+git add db/migrate/20260409200000_add_counter_proposal_to_requests.rb db/schema.rb
+git commit -m "feat: add proposed_scheduled_at and proposal_reason columns to requests"
+```
+
+---
+
+### Task 2: Request model — Add counter_proposed state and transitions
+
+**Files:**
+- Modify: `app/models/request.rb`
+- Modify: `spec/models/request_spec.rb`
+- Modify: `spec/factories/requests.rb`
+
+- [ ] **Step 1: Write failing model specs for new state machine transitions**
+
+Add to `spec/models/request_spec.rb`, inside the `"state machine"` describe block, after the existing `expire` tests:
+
+```ruby
+describe "counter_propose event" do
+  it "transitions from pending to counter_proposed" do
+    request.proposed_scheduled_at = 5.days.from_now
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
+describe "accept_proposal event" do
+  let(:request) { create(:request, :counter_proposed) }
+
+  it "transitions from counter_proposed to accepted" do
+    request.accept_proposal!
+    expect(request).to be_accepted
+    expect(request.accepted_at).to be_within(1.second).of(Time.current)
+  end
+
+  it "cannot accept_proposal from pending" do
+    pending_request = create(:request)
+    expect { pending_request.accept_proposal! }.to raise_error(AASM::InvalidTransition)
+  end
+end
+
+describe "decline_proposal event" do
+  let(:request) { create(:request, :counter_proposed) }
+
+  it "transitions from counter_proposed to pending" do
+    request.decline_proposal!
+    expect(request).to be_pending
+    expect(request.proposed_scheduled_at).to be_nil
+    expect(request.proposal_reason).to be_nil
+  end
+end
+```
+
+Add to `spec/models/request_spec.rb`, inside the `"validations"` describe block:
+
+```ruby
+context "when counter_proposed" do
+  it "requires proposed_scheduled_at" do
+    request = build(:request, :counter_proposed, proposed_scheduled_at: nil)
+    expect(request).not_to be_valid
+  end
+end
+```
+
+- [ ] **Step 2: Run tests to verify they fail**
+
+Run: `bundle exec rspec spec/models/request_spec.rb`
+Expected: FAIL — `counter_proposed` state and events not defined yet.
+
+- [ ] **Step 3: Add factory trait for counter_proposed**
+
+Add to `spec/factories/requests.rb`, after the `:expired` trait:
+
+```ruby
+trait :counter_proposed do
+  state { "counter_proposed" }
+  proposed_scheduled_at { 5.days.from_now }
+  proposal_reason { "I'm busy that day, how about this?" }
+end
+```
+
+- [ ] **Step 4: Update the Request model with new state, events, and validation**
+
+Replace the full `app/models/request.rb` content:
+
+```ruby
+class Request < ApplicationRecord
+  include AASM
+  include Paginatable
+
+  belongs_to :client
+  belongs_to :provider
+  has_one :order, dependent: :destroy
+
+  validates :scheduled_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :decline_reason, presence: true, if: -> { declined? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
+
+  scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
+  scope :past, -> { where("scheduled_at <= ?", Time.current) }
+  scope :by_state, ->(state) { where(state: state) if state.present? }
+  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
+  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
+  scope :scheduled_between, ->(from, to) {
+    scope = all
+    scope = scope.where("scheduled_at >= ?", from) if from.present?
+    scope = scope.where("scheduled_at <= ?", to) if to.present?
+    scope
+  }
+  scope :sorted, -> { order(scheduled_at: :desc) }
+
+  aasm column: :state do
+    state :pending, initial: true
+    state :accepted
+    state :declined
+    state :expired
+    state :counter_proposed
+
+    event :accept do
+      transitions from: :pending, to: :accepted
+      after do
+        update!(accepted_at: Time.current)
+      end
+    end
+
+    event :decline do
+      transitions from: :pending, to: :declined
+    end
+
+    event :expire do
+      transitions from: :pending, to: :expired
+      after do
+        update!(expired_at: Time.current)
+      end
+    end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(accepted_at: Time.current)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil, proposal_reason: nil)
+      end
+    end
+  end
+end
+```
+
+- [ ] **Step 5: Run tests to verify they pass**
+
+Run: `bundle exec rspec spec/models/request_spec.rb`
+Expected: All PASS.
+
+- [ ] **Step 6: Commit**
+
+```bash
+git add app/models/request.rb spec/models/request_spec.rb spec/factories/requests.rb
+git commit -m "feat: add counter_proposed state with transitions to Request model"
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
+```ruby
+# spec/services/requests/counter_propose_service_spec.rb
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
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy that day"
+        ).call
+
+        expect(read_notification_log).to include("event=request_counter_proposed")
+      end
+    end
+
+    context "without proposed_scheduled_at" do
+      it "returns error" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: nil,
+          reason: "I'm busy"
+        ).call
+
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
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy"
+        ).call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
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
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy"
+        ).call
+
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
+```
+
+- [ ] **Step 2: Run test to verify it fails**
+
+Run: `bundle exec rspec spec/services/requests/counter_propose_service_spec.rb`
+Expected: FAIL — `Requests::CounterProposeService` not defined.
+
+- [ ] **Step 3: Write the implementation**
+
+```ruby
+# app/services/requests/counter_propose_service.rb
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
+- [ ] **Step 4: Run test to verify it passes**
+
+Run: `bundle exec rspec spec/services/requests/counter_propose_service_spec.rb`
+Expected: All PASS.
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add app/services/requests/counter_propose_service.rb spec/services/requests/counter_propose_service_spec.rb
+git commit -m "feat: add CounterProposeService for provider time proposals"
+```
+
+---
+
+### Task 4: AcceptProposalService
+
+**Files:**
+- Create: `app/services/requests/accept_proposal_service.rb`
+- Create: `spec/services/requests/accept_proposal_service_spec.rb`
+
+- [ ] **Step 1: Write the failing test**
+
+```ruby
+# spec/services/requests/accept_proposal_service_spec.rb
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) do
+    create(:request,
+      client: client,
+      provider: provider,
+      state: "counter_proposed",
+      proposed_scheduled_at: proposed_time,
+      proposal_reason: "I'm busy that day"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the request and updates scheduled_at to proposed time" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+        expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "creates an order with the proposed time" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+
+        order = request.reload.order
+        expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(order.client).to eq(client)
+        expect(order.provider).to eq(provider)
+      end
+
+      it "creates a payment for the order" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Payment, :count).by(1)
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
+    context "when request is not counter_proposed" do
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
+```
+
+- [ ] **Step 2: Run test to verify it fails**
+
+Run: `bundle exec rspec spec/services/requests/accept_proposal_service_spec.rb`
+Expected: FAIL — `Requests::AcceptProposalService` not defined.
+
+- [ ] **Step 3: Write the implementation**
+
+```ruby
+# app/services/requests/accept_proposal_service.rb
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
+        @request.scheduled_at = @request.proposed_scheduled_at
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
+```
+
+- [ ] **Step 4: Run test to verify it passes**
+
+Run: `bundle exec rspec spec/services/requests/accept_proposal_service_spec.rb`
+Expected: All PASS.
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add app/services/requests/accept_proposal_service.rb spec/services/requests/accept_proposal_service_spec.rb
+git commit -m "feat: add AcceptProposalService for clients to accept counter-proposals"
+```
+
+---
+
+### Task 5: DeclineProposalService
+
+**Files:**
+- Create: `app/services/requests/decline_proposal_service.rb`
+- Create: `spec/services/requests/decline_proposal_service_spec.rb`
+
+- [ ] **Step 1: Write the failing test**
+
+```ruby
+# spec/services/requests/decline_proposal_service_spec.rb
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request,
+      client: client,
+      provider: provider,
+      state: "counter_proposed",
+      proposed_scheduled_at: 5.days.from_now,
+      proposal_reason: "I'm busy that day"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns request to pending and clears proposal fields" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.proposal_reason).to be_nil
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
+    context "when request is not counter_proposed" do
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
+```
+
+- [ ] **Step 2: Run test to verify it fails**
+
+Run: `bundle exec rspec spec/services/requests/decline_proposal_service_spec.rb`
+Expected: FAIL — `Requests::DeclineProposalService` not defined.
+
+- [ ] **Step 3: Write the implementation**
+
+```ruby
+# app/services/requests/decline_proposal_service.rb
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
+```
+
+- [ ] **Step 4: Run test to verify it passes**
+
+Run: `bundle exec rspec spec/services/requests/decline_proposal_service_spec.rb`
+Expected: All PASS.
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add app/services/requests/decline_proposal_service.rb spec/services/requests/decline_proposal_service_spec.rb
+git commit -m "feat: add DeclineProposalService for clients to decline counter-proposals"
+```
+
+---
+
+### Task 6: Routes and Controller
+
+**Files:**
+- Modify: `config/routes.rb`
+- Modify: `app/controllers/api/requests_controller.rb`
+
+- [ ] **Step 1: Add routes**
+
+In `config/routes.rb`, add three new member routes inside the `resources :requests` block, after the existing `decline` route:
+
+```ruby
+resources :requests, only: [:index, :show, :create] do
+  member do
+    patch :accept
+    patch :decline
+    patch :counter_propose
+    patch :accept_proposal
+    patch :decline_proposal
+  end
+end
+```
+
+- [ ] **Step 2: Add controller actions and update JSON serialization**
+
+In `app/controllers/api/requests_controller.rb`:
+
+Update the `before_action` line:
+
+```ruby
+before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_proposal, :decline_proposal]
+```
+
+Add three new actions after the `decline` action:
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
+    reason: params[:reason]
+  ).call
+  handle_service_result(result)
+end
+
+def accept_proposal
+  client = current_client!
+  return if performed?
+
+  result = Requests::AcceptProposalService.new(
+    request: @request,
+    client: client
+  ).call
+  handle_service_result(result)
+end
+
+def decline_proposal
+  client = current_client!
+  return if performed?
+
+  result = Requests::DeclineProposalService.new(
+    request: @request,
+    client: client
+  ).call
+  handle_service_result(result)
+end
+```
+
+Update `request_detail_json` to include the new fields:
+
+```ruby
+def request_detail_json(request)
+  {
+    id: request.id,
+    state: request.state,
+    scheduled_at: request.scheduled_at,
+    duration_minutes: request.duration_minutes,
+    location: request.location,
+    notes: request.notes,
+    decline_reason: request.decline_reason,
+    proposed_scheduled_at: request.proposed_scheduled_at,
+    proposal_reason: request.proposal_reason,
+    accepted_at: request.accepted_at,
+    expired_at: request.expired_at,
+    client_id: request.client_id,
+    provider_id: request.provider_id,
+    created_at: request.created_at,
+    updated_at: request.updated_at
+  }
+end
+```
+
+- [ ] **Step 3: Run full test suite**
+
+Run: `bundle exec rspec`
+Expected: All PASS.
+
+- [ ] **Step 4: Commit**
+
+```bash
+git add config/routes.rb app/controllers/api/requests_controller.rb
+git commit -m "feat: add counter_propose, accept_proposal, decline_proposal routes and controller actions"
+```
+
+---
+
+### Task 7: Full integration verification
+
+- [ ] **Step 1: Run full test suite one final time**
+
+Run: `bundle exec rspec`
+Expected: All tests pass, zero failures.
+
+- [ ] **Step 2: Verify routes**
+
+Run: `bin/rails routes | grep request`
+Expected: Output includes `counter_propose_api_request`, `accept_proposal_api_request`, `decline_proposal_api_request` routes.
+
+- [ ] **Step 3: Final commit (if any cleanup needed)**
+
+Only if tests revealed issues needing fixes.
diff --git a/app_delta/spec/factories/requests.rb b/app_delta/spec/factories/requests.rb
index 67c374a..c0ba169 100644
--- a/app_delta/spec/factories/requests.rb
+++ b/app_delta/spec/factories/requests.rb
@@ -21,5 +21,11 @@
       state { "expired" }
       expired_at { Time.current }
     end
+
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      proposal_reason { "I'm busy that day, how about this?" }
+    end
   end
 end
diff --git a/app_delta/spec/models/request_spec.rb b/app_delta/spec/models/request_spec.rb
index dec4a53..2b7bee8 100644
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
@@ -78,6 +85,47 @@
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
+    describe "accept_proposal event" do
+      let(:request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to accepted" do
+        freeze_time do
+          request.accept_proposal!
+          expect(request).to be_accepted
+          expect(request.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "cannot accept_proposal from pending" do
+        pending_request = create(:request)
+        expect { pending_request.accept_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_proposal event" do
+      let(:request) { create(:request, :counter_proposed) }
+
+      it "transitions from counter_proposed to pending" do
+        request.decline_proposal!
+        expect(request).to be_pending
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.proposal_reason).to be_nil
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/app_delta/spec/services/requests/accept_proposal_service_spec.rb b/app_delta/spec/services/requests/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..e4da12e
--- /dev/null
+++ b/app_delta/spec/services/requests/accept_proposal_service_spec.rb
@@ -0,0 +1,67 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) do
+    create(:request,
+      client: client,
+      provider: provider,
+      state: "counter_proposed",
+      proposed_scheduled_at: proposed_time,
+      proposal_reason: "I'm busy that day"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the request and updates scheduled_at to proposed time" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+        expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "creates an order with the proposed time" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Order, :count).by(1)
+
+        order = request.reload.order
+        expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(order.client).to eq(client)
+        expect(order.provider).to eq(provider)
+      end
+
+      it "creates a payment for the order" do
+        expect { described_class.new(request: request, client: client).call }
+          .to change(Payment, :count).by(1)
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
+    context "when request is not counter_proposed" do
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/requests/counter_propose_service_spec.rb b/app_delta/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..b8a4184
--- /dev/null
+++ b/app_delta/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,81 @@
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
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy that day"
+        ).call
+
+        expect(read_notification_log).to include("event=request_counter_proposed")
+      end
+    end
+
+    context "without proposed_scheduled_at" do
+      it "returns error" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: nil,
+          reason: "I'm busy"
+        ).call
+
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
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy"
+        ).call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Not your request")
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
+          proposed_scheduled_at: proposed_time,
+          reason: "I'm busy"
+        ).call
+
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/requests/decline_proposal_service_spec.rb b/app_delta/spec/services/requests/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..d76152c
--- /dev/null
+++ b/app_delta/spec/services/requests/decline_proposal_service_spec.rb
@@ -0,0 +1,52 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request,
+      client: client,
+      provider: provider,
+      state: "counter_proposed",
+      proposed_scheduled_at: 5.days.from_now,
+      proposal_reason: "I'm busy that day"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns request to pending and clears proposal fields" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.proposal_reason).to be_nil
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
+    context "when request is not counter_proposed" do
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
