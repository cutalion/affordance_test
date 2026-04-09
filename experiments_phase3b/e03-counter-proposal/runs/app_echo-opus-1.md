# Experiment: e03-counter-proposal
# App: app_echo | Model: opus | Run: 1
# Branch: debt_experiment/e03-counter-proposal/app_echo/opus/run-1

---

## Claude Output

All 154 tests pass (0 failures). Here's what was implemented:

**New state:** `counter_proposed` — added to the Request AASM state machine

**Flow:**
1. Provider calls `PATCH /api/requests/:id/counter_propose` with `proposed_scheduled_at` (and optional `message`) → request moves from `pending` → `counter_proposed`
2. Client calls `PATCH /api/requests/:id/accept_counter_proposal` → request moves to `accepted` with `scheduled_at` updated to the proposed time, payment created
3. Client calls `PATCH /api/requests/:id/decline_counter_proposal` → request returns to `pending` (proposal fields cleared), provider can try again

**Files created:**
- `db/migrate/20260409152727_add_counter_proposal_to_requests.rb` — adds `proposed_scheduled_at` and `counter_proposal_message` columns
- `app/services/requests/counter_propose_service.rb`
- `app/services/requests/accept_counter_proposal_service.rb`
- `app/services/requests/decline_counter_proposal_service.rb`
- `spec/services/requests/counter_propose_service_spec.rb`
- `spec/services/requests/accept_counter_proposal_service_spec.rb`
- `spec/services/requests/decline_counter_proposal_service_spec.rb`

**Files modified:**
- `app/models/request.rb` — new state, 3 new events, validation
- `app/controllers/api/requests_controller.rb` — 3 new actions, JSON includes proposal fields
- `config/routes.rb` — 3 new member routes
- `spec/factories/requests.rb` — `:counter_proposed` trait

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..7a8c93b 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,7 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject,
+                                       :counter_propose, :accept_counter_proposal, :decline_counter_proposal]
 
     def index
       requests = scoped_requests
@@ -104,6 +105,45 @@ def reject
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
+    def accept_counter_proposal
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
+    def decline_counter_proposal
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
@@ -156,6 +196,8 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        counter_proposal_message: request.counter_proposal_message,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         started_at: request.started_at,
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..4b95cdf 100644
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
@@ -78,5 +80,31 @@ class Request < ApplicationRecord
     event :reject do
       transitions from: [:accepted, :in_progress], to: :rejected
     end
+
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_counter_proposal do
+      transitions from: :counter_proposed, to: :accepted
+      after do
+        update!(
+          scheduled_at: proposed_scheduled_at,
+          proposed_scheduled_at: nil,
+          counter_proposal_message: nil,
+          accepted_at: Time.current
+        )
+      end
+    end
+
+    event :decline_counter_proposal do
+      transitions from: :counter_proposed, to: :pending
+      after do
+        update!(
+          proposed_scheduled_at: nil,
+          counter_proposal_message: nil
+        )
+      end
+    end
   end
 end
diff --git a/app_echo/app/services/requests/accept_counter_proposal_service.rb b/app_echo/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..e6da7f8
--- /dev/null
+++ b/app_echo/app/services/requests/accept_counter_proposal_service.rb
@@ -0,0 +1,41 @@
+module Requests
+  class AcceptCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      Request.transaction do
+        @request.accept_counter_proposal!
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
index 0000000..d224589
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
diff --git a/app_echo/app/services/requests/decline_counter_proposal_service.rb b/app_echo/app/services/requests/decline_counter_proposal_service.rb
new file mode 100644
index 0000000..080bd72
--- /dev/null
+++ b/app_echo/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,25 @@
+module Requests
+  class DeclineCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.decline_counter_proposal!
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
index da43a53..3df3ad5 100644
--- a/app_echo/config/routes.rb
+++ b/app_echo/config/routes.rb
@@ -18,6 +18,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :counter_propose
+        patch :accept_counter_proposal
+        patch :decline_counter_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/app_echo/db/migrate/20260409152727_add_counter_proposal_to_requests.rb b/app_echo/db/migrate/20260409152727_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..5d67d2e
--- /dev/null
+++ b/app_echo/db/migrate/20260409152727_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+    add_column :requests, :counter_proposal_message, :text
+  end
+end
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
index 4620d0c..991b9d0 100644
--- a/app_echo/spec/factories/requests.rb
+++ b/app_echo/spec/factories/requests.rb
@@ -47,6 +47,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      counter_proposal_message { "Can we do it later?" }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..990d289
--- /dev/null
+++ b/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb
@@ -0,0 +1,77 @@
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
+      it "accepts the counter-proposal and updates scheduled_at" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        request.reload
+        expect(request).to be_accepted
+        expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.counter_proposal_message).to be_nil
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
index 0000000..c38f7f2
--- /dev/null
+++ b/app_echo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,89 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with valid params" do
+      it "transitions to counter_proposed state" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time,
+          message: "Can we do it later?"
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload).to be_counter_proposed
+        expect(request.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(request.counter_proposal_message).to eq("Can we do it later?")
+      end
+
+      it "works without a message" do
+        result = described_class.new(
+          request: request,
+          provider: provider,
+          proposed_scheduled_at: proposed_time
+        ).call
+
+        expect(result[:success]).to be true
+        expect(request.reload.counter_proposal_message).to be_nil
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
+    context "when request is not pending" do
+      let(:request) { create(:request, :accepted, provider: provider) }
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
diff --git a/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..fcd12f5
--- /dev/null
+++ b/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,51 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterProposalService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) do
+    create(:request, :counter_proposed,
+      client: client,
+      provider: provider
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "returns request to pending state" do
+        result = described_class.new(request: request, client: client).call
+
+        expect(result[:success]).to be true
+        request.reload
+        expect(request).to be_pending
+        expect(request.proposed_scheduled_at).to be_nil
+        expect(request.counter_proposal_message).to be_nil
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
