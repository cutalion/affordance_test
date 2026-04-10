# Experiment: e03-counter-proposal
# App: app_charlie | Model: opus | Run: 1
# Branch: debt_experiment/e03-counter-proposal/app_charlie/opus/run-1

---

## Claude Output

All 136 tests pass (including the new ones). Here's a summary of what was implemented:

**Counter-proposal feature for booking requests:**

**New state machine flow:**
- `pending` → `counter_proposed` (provider proposes a different time)
- `counter_proposed` → `accepted` (client accepts the new time; scheduled_at is updated)
- `counter_proposed` → `pending` (client declines; provider can try again or accept/decline normally)
- `counter_proposed` → `canceled` (client can still cancel)

**Files changed:**
- **Migration** — `db/migrate/20260408140806_add_proposed_scheduled_at_to_requests.rb` — adds `proposed_scheduled_at` column
- **Model** — `app/models/request.rb` — new `counter_proposed` state, `counter_propose`, `accept_counter`, `decline_counter` events, validation for `proposed_scheduled_at`
- **Services:**
  - `app/services/requests/counter_propose_service.rb` — provider proposes a new time
  - `app/services/requests/accept_counter_service.rb` — client accepts (creates payment, updates schedule, holds payment if card exists)
  - `app/services/requests/decline_counter_service.rb` — client declines (returns to pending)
- **Controller** — `app/controllers/api/requests_controller.rb` — three new actions
- **Routes** — `PATCH /api/requests/:id/counter_propose`, `accept_counter`, `decline_counter`
- **Specs** — model specs for all new transitions + service specs for all three services
- **Factory** — `:counter_proposed` trait added

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..2fdf18f 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :complete, :cancel, :reject, :counter_propose, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -106,6 +106,44 @@ def reject
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
@@ -158,6 +196,7 @@ def request_detail_json(request)
         decline_reason: request.decline_reason,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        proposed_scheduled_at: request.proposed_scheduled_at,
         accepted_at: request.accepted_at,
         expired_at: request.expired_at,
         started_at: request.started_at,
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..1e860ab 100644
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
@@ -56,6 +58,24 @@ class Request < ApplicationRecord
       end
     end
 
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
+
     event :start do
       transitions from: :accepted, to: :in_progress
       after do
@@ -71,7 +91,7 @@ class Request < ApplicationRecord
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
index 0000000..b3390ec
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
diff --git a/app_charlie/db/migrate/20260408140806_add_proposed_scheduled_at_to_requests.rb b/app_charlie/db/migrate/20260408140806_add_proposed_scheduled_at_to_requests.rb
new file mode 100644
index 0000000..a95e8f4
--- /dev/null
+++ b/app_charlie/db/migrate/20260408140806_add_proposed_scheduled_at_to_requests.rb
@@ -0,0 +1,5 @@
+class AddProposedScheduledAtToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..494c1de 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140805) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -81,6 +81,7 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
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
diff --git a/app_charlie/spec/models/request_spec.rb b/app_charlie/spec/models/request_spec.rb
index a9aece5..e6d2721 100644
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
@@ -180,6 +188,80 @@
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
+      it "cannot counter-propose from accepted" do
+        request.accept!
+        expect { request.counter_propose! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_counter event" do
+      let(:proposed_time) { 5.days.from_now }
+
+      before do
+        request.update!(proposed_scheduled_at: proposed_time)
+        request.counter_propose!
+      end
+
+      it "transitions from counter_proposed to accepted" do
+        request.accept_counter!
+        expect(request).to be_accepted
+      end
+
+      it "updates scheduled_at to proposed time and clears proposed_scheduled_at" do
+        freeze_time do
+          request.accept_counter!
+          request.reload
+          expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+          expect(request.proposed_scheduled_at).to be_nil
+          expect(request.accepted_at).to be_within(1.second).of(Time.current)
+        end
+      end
+
+      it "cannot accept_counter from pending" do
+        pending_request = create(:request)
+        expect { pending_request.accept_counter! }.to raise_error(AASM::InvalidTransition)
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
+      it "cannot decline_counter from accepted" do
+        request.accept_counter!
+        expect { request.decline_counter! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "cancel from counter_proposed" do
+      it "transitions from counter_proposed to canceled" do
+        request.update!(proposed_scheduled_at: 5.days.from_now)
+        request.counter_propose!
+        request.update!(cancel_reason: "Changed my mind")
+        request.cancel!
+        expect(request).to be_canceled
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/app_charlie/spec/services/requests/accept_counter_service_spec.rb b/app_charlie/spec/services/requests/accept_counter_service_spec.rb
new file mode 100644
index 0000000..3fc567f
--- /dev/null
+++ b/app_charlie/spec/services/requests/accept_counter_service_spec.rb
@@ -0,0 +1,74 @@
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
+    context "when request is pending (not counter_proposed)" do
+      let(:pending_request) { create(:request, client: client) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/counter_propose_service_spec.rb b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
new file mode 100644
index 0000000..a6bfab9
--- /dev/null
+++ b/app_charlie/spec/services/requests/counter_propose_service_spec.rb
@@ -0,0 +1,54 @@
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
+      end
+
+      it "stores the proposed time" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(request.reload.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "notifies the client" do
+        described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(read_notification_log).to include("event=counter_proposed")
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
+    context "when already accepted" do
+      before { request.accept! }
+
+      it "returns error" do
+        result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/decline_counter_service_spec.rb b/app_charlie/spec/services/requests/decline_counter_service_spec.rb
new file mode 100644
index 0000000..e0c236b
--- /dev/null
+++ b/app_charlie/spec/services/requests/decline_counter_service_spec.rb
@@ -0,0 +1,46 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineCounterService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :counter_proposed, client: client, provider: provider, proposed_scheduled_at: 5.days.from_now) }
+
+  describe "#call" do
+    context "with correct client" do
+      it "declines the counter-proposal" do
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
+    context "when request is pending (not counter_proposed)" do
+      let(:pending_request) { create(:request, client: client) }
+
+      it "returns error" do
+        result = described_class.new(request: pending_request, client: client).call
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
