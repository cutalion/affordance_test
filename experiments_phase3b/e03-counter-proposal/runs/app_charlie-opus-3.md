# Experiment: e03-counter-proposal
# App: app_charlie | Model: opus | Run: 3
# Branch: debt_experiment/e03-counter-proposal/app_charlie/opus/run-3

---

## Claude Output

All done. Here's a summary of what was implemented:

**New state machine flow:**
- `pending` → `counter_proposed` (provider proposes a different time)
- `counter_proposed` → `accepted` (client accepts the new time — scheduled_at is updated, payment is created)
- `counter_proposed` → `pending` (client declines — request returns to pending for the provider to accept/decline/counter again)
- `counter_proposed` → `canceled` (client can still cancel)

**Files created:**
- `app/services/requests/counter_propose_service.rb` — provider proposes a new `proposed_scheduled_at`
- `app/services/requests/accept_counter_service.rb` — client accepts (updates time, creates payment, holds if card exists)
- `app/services/requests/decline_counter_service.rb` — client declines (returns to pending)
- `spec/services/requests/counter_propose_service_spec.rb` — 7 tests
- `spec/services/requests/accept_counter_service_spec.rb` — 9 tests
- `spec/services/requests/decline_counter_service_spec.rb` — 5 tests

**Files modified:**
- `app/models/request.rb` — added `counter_proposed` state, 3 events, validation
- `app/controllers/api/requests_controller.rb` — 3 new actions, `proposed_scheduled_at` in JSON
- `config/routes.rb` — 3 new member routes
- `spec/factories/requests.rb` — `:counter_proposed` trait

**API endpoints:**
- `PATCH /api/requests/:id/counter_propose` (provider, params: `proposed_scheduled_at`)
- `PATCH /api/requests/:id/accept_counter` (client)
- `PATCH /api/requests/:id/decline_counter` (client)

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..eab69a0 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :counter_propose, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -106,6 +106,40 @@ def reject
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
@@ -155,6 +189,7 @@ def request_detail_json(request)
         notes: request.notes,
         amount_cents: request.amount_cents,
         currency: request.currency,
+        proposed_scheduled_at: request.proposed_scheduled_at,
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..947856f 100644
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
@@ -71,11 +73,29 @@ class Request < ApplicationRecord
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
+        update!(scheduled_at: proposed_scheduled_at, proposed_scheduled_at: nil, accepted_at: Time.current)
+      end
+    end
+
+    event :decline_counter do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil)
+      end
+    end
   end
 end
diff --git a/app_charlie/app/services/requests/accept_counter_service.rb b/app_charlie/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..e26234f
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
+      NotificationService.notify(@request.provider, :counter_proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter proposal in #{@request.state} state")
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
index 0000000..1fd051f
--- /dev/null
+++ b/app_charlie/app/services/requests/counter_propose_service.rb
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
+      error("Cannot counter propose request in #{@request.state} state")
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
index 0000000..b6377d9
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
+      NotificationService.notify(@request.provider, :counter_proposal_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline counter proposal in #{@request.state} state")
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
index e317a7f..2557868 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
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
diff --git a/app_charlie/db/migrate/20260409150903_add_counter_proposal_fields_to_requests.rb b/app_charlie/db/migrate/20260409150903_add_counter_proposal_fields_to_requests.rb
new file mode 100644
index 0000000..afaa7ad
--- /dev/null
+++ b/app_charlie/db/migrate/20260409150903_add_counter_proposal_fields_to_requests.rb
@@ -0,0 +1,7 @@
+class AddCounterProposalFieldsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    unless column_exists?(:requests, :proposed_scheduled_at)
+      add_column :requests, :proposed_scheduled_at, :datetime
+    end
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 4757a0b..9bfa7a7 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_081113) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_150903) do
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
index dad8264..2cc96df 100644
--- a/app_charlie/spec/factories/requests.rb
+++ b/app_charlie/spec/factories/requests.rb
@@ -47,6 +47,11 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_charlie/spec/services/requests/accept_counter_service_spec.rb b/app_charlie/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..02b78db
--- /dev/null
+++ b/app_charlie/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,75 @@
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
+      it "clears proposed_scheduled_at" do
+        described_class.new(request: request, client: client).call
+        expect(request.reload.proposed_scheduled_at).to be_nil
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
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot accept counter proposal")
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/counter_propose_service_spec.rb b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..855096f
--- /dev/null
+++ b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,62 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+
+  describe "#call" do
+    let(:proposed_time) { 5.days.from_now }
+
+    context "with correct provider and valid proposed time" do
+      it "moves request to counter_proposed state" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+      end
+
+      it "stores the proposed time" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "does not change the original scheduled_at" do
+        original_time = request.scheduled_at
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(request.reload.scheduled_at).to eq(original_time)
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
+    context "without proposed time" do
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: nil).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Proposed time is required")
+      end
+    end
+
+    context "when request is not pending" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot counter propose")
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/decline_counter_service_spec.rb b/app_charlie/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..55445da
--- /dev/null
+++ b/app_charlie/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,47 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "moves request back to pending" do
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
+    context "when request is not counter_proposed" do
+      let(:request) { create(:request, client: client, provider: provider) }
+
+      it "returns error" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Cannot decline counter proposal")
+      end
+    end
+  end
+end
```
