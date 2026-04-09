# Experiment: e03-counter-proposal
# App: app_charlie | Model: opus | Run: 1
# Branch: debt_experiment/e03-counter-proposal/app_charlie/opus/run-1

---

## Claude Output

All done. Here's what was implemented:

**Counter-proposal flow:**

1. **Provider counter-proposes** — `PATCH /api/requests/:id/counter_propose` with `proposed_scheduled_at` and optional `note`. Transitions request from `pending` → `counter_proposed`.

2. **Client accepts proposal** — `PATCH /api/requests/:id/accept_proposal`. Transitions `counter_proposed` → `accepted`, updates `scheduled_at` to the proposed time, creates a payment (same as normal accept).

3. **Client declines proposal** — `PATCH /api/requests/:id/decline_proposal`. Transitions `counter_proposed` → `pending`, clears proposal fields. The provider can then accept, decline, or counter-propose again.

**Files changed/created:**
- `db/migrate/..._add_counter_proposal_fields_to_requests.rb` — adds `proposed_scheduled_at` and `proposal_note` columns
- `app/models/request.rb` — new `counter_proposed` state, 3 AASM events, cancel also allowed from `counter_proposed`
- `app/services/requests/counter_propose_service.rb` (new)
- `app/services/requests/accept_proposal_service.rb` (new)
- `app/services/requests/decline_proposal_service.rb` (new)
- `app/controllers/api/requests_controller.rb` — 3 new actions, JSON includes new fields
- `config/routes.rb` — 3 new member routes
- `spec/factories/requests.rb` — `:counter_proposed` trait
- 3 new service specs + model spec updates

**134 tests, 0 failures.**

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..3b646e7 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :counter_propose, :accept_proposal, :decline_proposal]
 
     def index
       requests = scoped_requests
@@ -106,6 +106,45 @@ def reject
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
     private
 
     def set_request
@@ -158,6 +197,8 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        proposal_note: request.proposal_note,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         started_at: request.started_at,
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..b541362 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -37,6 +37,7 @@ class Request < ApplicationRecord
     state :expired
     state :canceled
     state :rejected
+    state :counter_proposed
 
     event :accept do
       transitions from: :pending, to: :accepted
@@ -71,11 +72,32 @@ class Request < ApplicationRecord
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
+    event :accept_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(
+          scheduled_at: proposed_scheduled_at,
+          accepted_at: Time.current
+        )
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil, proposal_note: nil)
+      end
+    end
   end
 end
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
index 0000000..773dd9e
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
index e317a7f..5fb9f89 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -18,6 +18,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :counter_propose
+        patch :accept_proposal
+        patch :decline_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/app_charlie/db/migrate/20260409145810_add_counter_proposal_fields_to_requests.rb b/app_charlie/db/migrate/20260409145810_add_counter_proposal_fields_to_requests.rb
new file mode 100644
index 0000000..804de07
--- /dev/null
+++ b/app_charlie/db/migrate/20260409145810_add_counter_proposal_fields_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalFieldsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :proposal_note, :text
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 4757a0b..11382a7 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_081113) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_145810) do
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
index dad8264..b754a8e 100644
--- a/app_charlie/spec/factories/requests.rb
+++ b/app_charlie/spec/factories/requests.rb
@@ -47,6 +47,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      proposal_note { "How about this time instead?" }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_charlie/spec/models/request_spec.rb b/app_charlie/spec/models/request_spec.rb
index a9aece5..00402bb 100644
--- a/app_charlie/spec/models/request_spec.rb
+++ b/app_charlie/spec/models/request_spec.rb
@@ -180,6 +180,72 @@
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
+    describe "accept_proposal event" do
+      before do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.counter_propose!
+      end
+
+      it "transitions from counter_proposed to accepted" do
+        request.accept_proposal!
+        expect(request).to be_accepted
+      end
+
+      it "sets accepted_at timestamp" do
+        freeze_time do
+          request.accept_proposal!
+          expect(request.reload.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "updates scheduled_at to proposed_scheduled_at" do
+        proposed_time = request.proposed_scheduled_at
+        request.accept_proposal!
+        expect(request.reload.scheduled_at).to eq(proposed_time)
+      end
+
+      it "cannot accept_proposal from pending" do
+        other_request = create(:request)
+        expect { other_request.accept_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_proposal event" do
+      before do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.counter_propose!
+      end
+
+      it "transitions from counter_proposed to pending" do
+        request.decline_proposal!
+        expect(request).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        request.decline_proposal!
+        expect(request.reload.proposed_scheduled_at).to be_nil
+      end
+
+      it "clears proposal_note" do
+        request.update!(proposal_note: "How about Tuesday?")
+        request.decline_proposal!
+        expect(request.reload.proposal_note).to be_nil
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/app_charlie/spec/services/requests/accept_proposal_service_spec.rb b/app_charlie/spec/services/requests/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..7a9b946
--- /dev/null
+++ b/app_charlie/spec/services/requests/accept_proposal_service_spec.rb
@@ -0,0 +1,59 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider, proposed_scheduled_at: proposed_time) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "accepts the proposal" do
+        result = described_class.new(request: request, client: client).call
+
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
+
+        payment = request.reload.payment
+        expect(payment.amount_cents).to eq(request.amount_cents)
+        expect(payment.status).to eq("pending")
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
+
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
+
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/counter_propose_service_spec.rb b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..d0b3619
--- /dev/null
+++ b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,96 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and valid params" do
+      it "transitions to counter_proposed" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          note: "How about Tuesday?"
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+      end
+
+      it "stores the proposed time" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "stores the proposal note" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          note: "Tuesday works better"
+        ).call
+
+        expect(request.reload.proposal_note).to eq("Tuesday works better")
+      end
+
+      it "notifies the client" do
+        described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
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
+    context "when already accepted" do
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
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/decline_proposal_service_spec.rb b/app_charlie/spec/services/requests/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..742fc6f
--- /dev/null
+++ b/app_charlie/spec/services/requests/decline_proposal_service_spec.rb
@@ -0,0 +1,54 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns to pending state" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.proposed_scheduled_at).to be_nil
+      end
+
+      it "clears proposal_note" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.proposal_note).to be_nil
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
+
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
+
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
