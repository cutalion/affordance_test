# Experiment: e03-counter-proposal
# App: app_charlie | Model: opus | Run: 2
# Branch: debt_experiment/e03-counter-proposal/app_charlie/opus/run-2

---

## Claude Output

All done. Here's a summary of what was implemented:

**Counter-proposal feature** — 133 tests passing, 0 failures.

**State machine flow:**
- `pending` → provider calls `counter_propose` → `counter_proposed`
- `counter_proposed` → client calls `accept_proposal` → `accepted` (scheduled_at updated to proposed time, payment created)
- `counter_proposed` → client calls `decline_proposal` → `pending` (proposal fields cleared, provider can try again)
- `counter_proposed` → client can also `cancel` the request entirely

**Files created:**
- `db/migrate/..._add_counter_proposal_to_requests.rb` — adds `proposed_scheduled_at` and `proposal_note` columns
- `app/services/requests/counter_propose_service.rb` — provider proposes a new time
- `app/services/requests/accept_proposal_service.rb` — client accepts (creates payment, holds if card exists)
- `app/services/requests/decline_proposal_service.rb` — client declines, request returns to pending
- `spec/services/requests/counter_propose_service_spec.rb` — 6 examples
- `spec/services/requests/accept_proposal_service_spec.rb` — 7 examples
- `spec/services/requests/decline_proposal_service_spec.rb` — 5 examples

**Files modified:**
- `app/models/request.rb` — new `counter_proposed` state, `counter_propose`, `accept_proposal`, `decline_proposal` events, cancel now allowed from `counter_proposed`
- `app/controllers/api/requests_controller.rb` — 3 new actions, JSON includes `proposed_scheduled_at` and `proposal_note`
- `config/routes.rb` — 3 new member routes
- `spec/models/request_spec.rb` — model specs for new transitions and validation
- `spec/factories/requests.rb` — `:counter_proposed` trait

**API endpoints:**
- `PATCH /api/requests/:id/counter_propose` (provider, requires `proposed_scheduled_at`, optional `note`)
- `PATCH /api/requests/:id/accept_proposal` (client)
- `PATCH /api/requests/:id/decline_proposal` (client)

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..a1717f8 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :counter_propose, :accept_proposal, :decline_proposal, :start, :complete, :cancel, :reject]
 
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
+        note: params[:note]
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
     def start
       provider = current_provider!
       return if performed?
@@ -155,6 +194,8 @@ def request_detail_json(request)
         notes: request.notes,
         amount_cents: request.amount_cents,
         currency: request.currency,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        proposal_note: request.proposal_note,
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..ee1752e 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -14,6 +14,7 @@ class Request < ApplicationRecord
   validates :decline_reason, presence: true, if: -> { declined? }
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -37,6 +38,7 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -49,6 +51,24 @@ class Request < ApplicationRecord
       transitions from: :pending, to: :declined
     end
 
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(scheduled_at: proposed_scheduled_at, accepted_at: Time.current)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil, proposal_note: nil)
+      end
+    end
+
     event :expire do
       transitions from: :pending, to: :expired
       after do
@@ -71,7 +91,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :accepted], to: :canceled
+      transitions from: [:pending, :accepted, :counter_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/app_charlie/app/services/requests/accept_proposal_service.rb b/app_charlie/app/services/requests/accept_proposal_service.rb
new file mode 100644
index 0000000..e896f62
--- /dev/null
+++ b/app_charlie/app/services/requests/accept_proposal_service.rb
@@ -0,0 +1,41 @@
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
+      NotificationService.notify(@request.provider, :proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept proposal for request in #{@request.state} state")
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
index 0000000..5168219
--- /dev/null
+++ b/app_charlie/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,30 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_scheduled_at:, note: nil)
+      @request = request
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+      @note = note
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @request.proposed_scheduled_at = @proposed_scheduled_at
+      @request.proposal_note = @note
+      @request.counter_propose!
+
+      NotificationService.notify(@request.client, :counter_proposal, request_id: @request.id)
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
diff --git a/app_charlie/app/services/requests/decline_proposal_service.rb b/app_charlie/app/services/requests/decline_proposal_service.rb
new file mode 100644
index 0000000..71260ea
--- /dev/null
+++ b/app_charlie/app/services/requests/decline_proposal_service.rb
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
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..a6aa1c7 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -14,6 +14,9 @@
       member do
         patch :accept
         patch :decline
+        patch :counter_propose
+        patch :accept_proposal
+        patch :decline_proposal
         patch :start
         patch :complete
         patch :cancel
diff --git a/app_charlie/db/migrate/20260409150325_add_counter_proposal_to_requests.rb b/app_charlie/db/migrate/20260409150325_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..98db928
--- /dev/null
+++ b/app_charlie/db/migrate/20260409150325_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime unless column_exists?(:requests, :proposed_scheduled_at)
+    add_column :requests, :proposal_note, :text unless column_exists?(:requests, :proposal_note)
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 4757a0b..01b38ca 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_081113) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_150325) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -81,6 +81,8 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_note"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.string "recurring_group_id"
     t.integer "recurring_index"
diff --git a/app_charlie/spec/factories/requests.rb b/app_charlie/spec/factories/requests.rb
index dad8264..4597f8c 100644
--- a/app_charlie/spec/factories/requests.rb
+++ b/app_charlie/spec/factories/requests.rb
@@ -47,6 +47,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      proposal_note { "I'm available at this time instead" }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_charlie/spec/models/request_spec.rb b/app_charlie/spec/models/request_spec.rb
index a9aece5..b23a43d 100644
--- a/app_charlie/spec/models/request_spec.rb
+++ b/app_charlie/spec/models/request_spec.rb
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
@@ -153,6 +161,14 @@
         expect(request).to be_canceled
       end
 
+      it "transitions from counter_proposed to canceled" do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.counter_propose!
+        request.update!(cancel_reason: "Changed my mind")
+        request.cancel!
+        expect(request).to be_canceled
+      end
+
       it "cannot cancel from in_progress" do
         request.accept!
         request.start!
@@ -160,6 +176,64 @@
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
+    describe "accept_proposal event" do
+      let(:proposed_time) { 5.days.from_now }
+
+      before do
+        request.update!(proposed_scheduled_at: proposed_time)
+        request.counter_propose!
+      end
+
+      it "transitions from counter_proposed to accepted" do
+        request.accept_proposal!
+        expect(request).to be_accepted
+      end
+
+      it "updates scheduled_at to proposed_scheduled_at" do
+        request.accept_proposal!
+        expect(request.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "sets accepted_at timestamp" do
+        freeze_time do
+          request.accept_proposal!
+          expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+    end
+
+    describe "decline_proposal event" do
+      before do
+        request.update!(proposed_scheduled_at: 5.days.from_now, proposal_note: "Better time")
+        request.counter_propose!
+      end
+
+      it "transitions from counter_proposed to pending" do
+        request.decline_proposal!
+        expect(request).to be_pending
+      end
+
+      it "clears proposal fields" do
+        request.decline_proposal!
+        request.reload
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.proposal_note).to be_nil
+      end
+    end
+
     describe "reject event" do
       it "transitions from accepted to rejected" do
         request.accept!
diff --git a/app_charlie/spec/services/requests/accept_proposal_service_spec.rb b/app_charlie/spec/services/requests/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..f22bafb
--- /dev/null
+++ b/app_charlie/spec/services/requests/accept_proposal_service_spec.rb
@@ -0,0 +1,75 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposalService do
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
+      it "accepts the proposal and updates scheduled_at" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_accepted
+        expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.accepted_at).to be_present
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
+        expect(result[:error]).to include("Cannot accept proposal")
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/counter_propose_service_spec.rb b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..0282ddf
--- /dev/null
+++ b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,90 @@
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
+          note: "I'm available at this time instead"
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.proposal_note).to eq("I'm available at this time instead")
+      end
+
+      it "works without a note" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposal_note).to be_nil
+      end
+
+      it "notifies the client" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
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
+          proposed_scheduled_at: proposed_time
+        ).call
+
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
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/decline_proposal_service_spec.rb b/app_charlie/spec/services/requests/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..8b8aaa8
--- /dev/null
+++ b/app_charlie/spec/services/requests/decline_proposal_service_spec.rb
@@ -0,0 +1,53 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request, :counter_proposed, client: client, provider: provider)
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "transitions request back to pending" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears the proposal fields" do
+        described_class.new(request: request, client: client).call
+
+        request.reload
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.proposal_note).to be_nil
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
+        expect(result[:error]).to include("Cannot decline proposal")
+      end
+    end
+  end
+end
```
