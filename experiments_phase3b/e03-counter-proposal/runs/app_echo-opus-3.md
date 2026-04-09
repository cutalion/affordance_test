# Experiment: e03-counter-proposal
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e03-counter-proposal/app_echo/opus/run-3

---

## Claude Output

All done. Here's what was implemented:

**Counter-proposal feature** — providers can propose a different time for a booking, and clients can accept or decline.

### Flow
1. **Provider counter-proposes** (`PATCH /api/requests/:id/counter_propose`) — sends `proposed_scheduled_at` and optional `message`. Request moves from `pending` → `counter_proposed`.
2. **Client accepts** (`PATCH /api/requests/:id/accept_counter_proposal`) — `scheduled_at` is updated to the proposed time, request moves to `accepted`, payment is created.
3. **Client declines** (`PATCH /api/requests/:id/decline_counter_proposal`) — proposal fields are cleared, request reverts to `pending` so the provider can accept, decline, or counter-propose again.

### Files changed
- **`app/models/request.rb`** — added `counter_proposed` state, `counter_propose` and `revert_to_pending` events, validation for `proposed_scheduled_at`, and expanded existing transitions (`accept`, `decline`, `expire`, `cancel`) to also work from `counter_proposed`
- **`config/routes.rb`** — 3 new member routes
- **`app/controllers/api/requests_controller.rb`** — 3 new actions, `proposed_scheduled_at` and `counter_proposal_message` in JSON response
- **`app/services/requests/counter_propose_service.rb`** — new
- **`app/services/requests/accept_counter_proposal_service.rb`** — new
- **`app/services/requests/decline_counter_proposal_service.rb`** — new
- **`spec/factories/requests.rb`** — `:counter_proposed` trait
- **3 new spec files** — 20 tests covering all happy paths and error cases

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..b20b53f 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :counter_propose, :accept_counter_proposal, :decline_counter_proposal]
 
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
+        return render_unprocessable(["Proposed scheduled time is required"])
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
@@ -153,6 +192,8 @@ def request_detail_json(request)
         notes: request.notes,
         amount_cents: request.amount_cents,
         currency: request.currency,
+        proposed_scheduled_at: request.proposed_scheduled_at,
+        counter_proposal_message: request.counter_proposal_message,
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..032ca0f 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -15,6 +15,7 @@ class Request < ApplicationRecord
   validates :decline_reason, presence: true, if: -> { declined? }
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -38,25 +39,34 @@ class Request < ApplicationRecord
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
-      transitions from: :pending, to: :expired
+      transitions from: [:pending, :counter_proposed], to: :expired
       after do
         update!(expired_at: Time.current)
       end
     end
 
+    event :counter_propose do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :revert_to_pending do
+      transitions from: :counter_proposed, to: :pending
+    end
+
     event :start do
       transitions from: :accepted, to: :in_progress
       after do
@@ -72,7 +82,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :accepted], to: :canceled
+      transitions from: [:pending, :accepted, :counter_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/app_echo/app/services/requests/accept_counter_proposal_service.rb b/app_echo/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..fd54d4e
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
+      return error("Cannot accept counter-proposal for request in #{@request.state} state") unless @request.counter_proposed?
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
index 0000000..7e7f123
--- /dev/null
+++ b/app_echo/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,28 @@
+module Requests
+  class DeclineCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+      return error("Cannot decline counter-proposal for request in #{@request.state} state") unless @request.counter_proposed?
+
+      @request.proposed_scheduled_at = nil
+      @request.counter_proposal_message = nil
+      @request.revert_to_pending!
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
index 4620d0c..373933e 100644
--- a/app_echo/spec/factories/requests.rb
+++ b/app_echo/spec/factories/requests.rb
@@ -63,6 +63,12 @@
       scheduled_at { 1.day.from_now }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+      counter_proposal_message { "Can we do it later?" }
+    end
+
     trait :announcement_response do
       announcement { association :announcement, :published }
       response_message { "I can help with that" }
diff --git a/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb b/app_echo/spec/services/requests/accept_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..15bc7bc
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
index 0000000..253189b
--- /dev/null
+++ b/app_echo/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,60 @@
+require "rails_helper"
+
+RSpec.describe Requests::CounterProposeService do
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    context "with correct provider and proposed time" do
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
+      it "stores an optional message" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time, message: "Morning works better").call
+        expect(request.reload.counter_proposal_message).to eq("Morning works better")
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(read_notification_log).to include("event=counter_proposal")
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
+        expect(result[:error]).to include("Cannot counter-propose")
+      end
+    end
+  end
+end
diff --git a/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb b/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb
new file mode 100644
index 0000000..e4a56e6
--- /dev/null
+++ b/app_echo/spec/services/requests/decline_counter_proposal_service_spec.rb
@@ -0,0 +1,56 @@
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
+      counter_proposal_message: "Can we do it later?"
+    )
+  end
+
+  describe "#call" do
+    context "with correct client" do
+      it "reverts request to pending" do
+        result = described_class.new(request: request, client: client).call
+        expect(result[:success]).to be true
+        expect(request.reload).to be_pending
+      end
+
+      it "clears the proposed time and message" do
+        described_class.new(request: request, client: client).call
+        request.reload
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
