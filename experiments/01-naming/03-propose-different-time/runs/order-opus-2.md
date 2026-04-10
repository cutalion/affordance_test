# Experiment: 03-propose-different-time
# App: order | Model: opus | Run: 2
# Branch: experiment/03-propose-different-time/order/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**New state: `provider_proposed`** — added to the AASM state machine between `pending` and `confirmed`/`canceled`.

**New flow:**
1. Provider calls `PATCH /api/orders/:id/propose_new_time` with `proposed_scheduled_at` (and optional `proposed_duration_minutes`) — order moves from `pending` → `provider_proposed`
2. Client calls `PATCH /api/orders/:id/accept_proposal` — order moves to `confirmed` and `scheduled_at`/`duration_minutes` are updated to the proposed values
3. Client calls `PATCH /api/orders/:id/decline_proposal` (with optional `reason`) — order moves to `canceled`

**Files changed:**
- Migration adding `proposed_scheduled_at` and `proposed_duration_minutes` columns
- `Order` model — new states, events, validation
- 3 new services: `ProposeNewTimeService`, `AcceptProposalService`, `DeclineProposalService`
- Controller with 3 new actions + routes
- Full test coverage (300 tests, all passing)

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..a3c80d4 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_new_time, :accept_proposal, :decline_proposal]
 
     def index
       orders = scoped_orders
@@ -90,6 +90,43 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_new_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_scheduled_at].blank?
+        return render_unprocessable(["Proposed scheduled time is required"])
+      end
+
+      result = Orders::ProposeNewTimeService.new(
+        order: @order,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at],
+        proposed_duration_minutes: params[:proposed_duration_minutes]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_proposal
+      client = current_client!
+      return if performed?
+
+      result = Orders::AcceptProposalService.new(order: @order, client: client).call
+      handle_service_result(result)
+    end
+
+    def decline_proposal
+      client = current_client!
+      return if performed?
+
+      result = Orders::DeclineProposalService.new(
+        order: @order,
+        client: client,
+        reason: params[:reason]
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_order
@@ -141,6 +178,8 @@ def order_detail_json(order)
         currency: order.currency,
         cancel_reason: order.cancel_reason,
         reject_reason: order.reject_reason,
+        proposed_scheduled_at: order.proposed_scheduled_at,
+        proposed_duration_minutes: order.proposed_duration_minutes,
         started_at: order.started_at,
         completed_at: order.completed_at,
         client_id: order.client_id,
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..f8f0439 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -13,6 +13,7 @@ class Order < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { provider_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -29,6 +30,7 @@ class Order < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :provider_proposed
     state :confirmed
     state :in_progress
     state :completed
@@ -39,6 +41,24 @@ class Order < ApplicationRecord
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_new_time do
+      transitions from: :pending, to: :provider_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :provider_proposed, to: :confirmed
+      after do
+        update!(
+          scheduled_at: proposed_scheduled_at,
+          duration_minutes: proposed_duration_minutes || duration_minutes
+        )
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :provider_proposed, to: :canceled
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
diff --git a/affordance_order/app/services/orders/accept_proposal_service.rb b/affordance_order/app/services/orders/accept_proposal_service.rb
new file mode 100644
index 0000000..8541d72
--- /dev/null
+++ b/affordance_order/app/services/orders/accept_proposal_service.rb
@@ -0,0 +1,25 @@
+module Orders
+  class AcceptProposalService
+    def initialize(order:, client:)
+      @order = order
+      @client = client
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+
+      @order.accept_proposal!
+
+      NotificationService.notify(@order.provider, :proposal_accepted, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot accept proposal for order in #{@order.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_order/app/services/orders/decline_proposal_service.rb b/affordance_order/app/services/orders/decline_proposal_service.rb
new file mode 100644
index 0000000..e870498
--- /dev/null
+++ b/affordance_order/app/services/orders/decline_proposal_service.rb
@@ -0,0 +1,27 @@
+module Orders
+  class DeclineProposalService
+    def initialize(order:, client:, reason: nil)
+      @order = order
+      @client = client
+      @reason = reason
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+
+      @order.cancel_reason = @reason.presence || "Declined counter-proposal"
+      @order.decline_proposal!
+
+      NotificationService.notify(@order.provider, :proposal_declined, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot decline proposal for order in #{@order.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_order/app/services/orders/propose_new_time_service.rb b/affordance_order/app/services/orders/propose_new_time_service.rb
new file mode 100644
index 0000000..202f3b3
--- /dev/null
+++ b/affordance_order/app/services/orders/propose_new_time_service.rb
@@ -0,0 +1,31 @@
+module Orders
+  class ProposeNewTimeService
+    def initialize(order:, provider:, proposed_scheduled_at:, proposed_duration_minutes: nil)
+      @order = order
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+      @proposed_duration_minutes = proposed_duration_minutes
+    end
+
+    def call
+      return error("Not your order") unless @order.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @order.proposed_scheduled_at = @proposed_scheduled_at
+      @order.proposed_duration_minutes = @proposed_duration_minutes
+      @order.propose_new_time!
+
+      NotificationService.notify(@order.client, :new_time_proposed, order_id: @order.id,
+        proposed_scheduled_at: @proposed_scheduled_at)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot propose new time for order in #{@order.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..fd7531e 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -17,6 +17,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :propose_new_time
+        patch :accept_proposal
+        patch :decline_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_order/db/migrate/20260407113616_add_counter_proposal_fields_to_orders.rb b/affordance_order/db/migrate/20260407113616_add_counter_proposal_fields_to_orders.rb
new file mode 100644
index 0000000..43e11ef
--- /dev/null
+++ b/affordance_order/db/migrate/20260407113616_add_counter_proposal_fields_to_orders.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalFieldsToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :proposed_scheduled_at, :datetime
+    add_column :orders, :proposed_duration_minutes, :integer
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..18facd5 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_113616) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -46,6 +46,8 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.integer "proposed_duration_minutes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_order/spec/factories/orders.rb b/affordance_order/spec/factories/orders.rb
index 81b3def..1870ceb 100644
--- a/affordance_order/spec/factories/orders.rb
+++ b/affordance_order/spec/factories/orders.rb
@@ -9,6 +9,11 @@
     amount_cents { 350_000 }
     currency { "RUB" }
 
+    trait :provider_proposed do
+      state { "provider_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :confirmed do
       state { "confirmed" }
     end
diff --git a/affordance_order/spec/models/order_spec.rb b/affordance_order/spec/models/order_spec.rb
index 6686df0..128bf62 100644
--- a/affordance_order/spec/models/order_spec.rb
+++ b/affordance_order/spec/models/order_spec.rb
@@ -45,6 +45,14 @@
         expect(order.errors[:reject_reason]).to be_present
       end
     end
+
+    context "when provider_proposed" do
+      it "requires proposed_scheduled_at" do
+        order = build(:order, :provider_proposed, proposed_scheduled_at: nil)
+        expect(order).not_to be_valid
+        expect(order.errors[:proposed_scheduled_at]).to be_present
+      end
+    end
   end
 
   describe "state machine" do
@@ -67,6 +75,59 @@
       end
     end
 
+    describe "propose_new_time event" do
+      it "transitions from pending to provider_proposed" do
+        order.proposed_scheduled_at = 5.days.from_now
+        order.propose_new_time!
+        expect(order).to be_provider_proposed
+      end
+
+      it "cannot propose from confirmed state" do
+        order.confirm!
+        expect { order.propose_new_time! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_proposal event" do
+      let(:proposed_time) { 5.days.from_now }
+
+      before do
+        order.update!(proposed_scheduled_at: proposed_time, state: "provider_proposed")
+      end
+
+      it "transitions from provider_proposed to confirmed" do
+        order.accept_proposal!
+        expect(order).to be_confirmed
+      end
+
+      it "updates scheduled_at to the proposed time" do
+        order.accept_proposal!
+        expect(order.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+      end
+
+      it "cannot accept from pending state" do
+        pending_order = create(:order)
+        expect { pending_order.accept_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "decline_proposal event" do
+      before do
+        order.update!(proposed_scheduled_at: 5.days.from_now, state: "provider_proposed",
+          cancel_reason: "Declined counter-proposal")
+      end
+
+      it "transitions from provider_proposed to canceled" do
+        order.decline_proposal!
+        expect(order).to be_canceled
+      end
+
+      it "cannot decline from pending state" do
+        pending_order = create(:order)
+        expect { pending_order.decline_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
     describe "start event" do
       before { order.confirm! }
 
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..f0ec3cb 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -180,4 +180,71 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/orders/:id/propose_new_time" do
+    let(:order) { create(:order, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "proposes a new time as provider" do
+      patch "/api/orders/#{order.id}/propose_new_time",
+        params: { proposed_scheduled_at: proposed_time },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("provider_proposed")
+      expect(body["proposed_scheduled_at"]).to be_present
+    end
+
+    it "returns 403 for client" do
+      patch "/api/orders/#{order.id}/propose_new_time",
+        params: { proposed_scheduled_at: proposed_time },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/orders/#{order.id}/propose_new_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/accept_proposal" do
+    let(:order) { create(:order, :provider_proposed, client: client, provider: provider) }
+
+    it "accepts the proposal as client" do
+      patch "/api/orders/#{order.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+      expect(body["scheduled_at"]).to eq(order.proposed_scheduled_at.as_json)
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/accept_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/decline_proposal" do
+    let(:order) { create(:order, :provider_proposed, client: client, provider: provider) }
+
+    it "declines the proposal as client" do
+      patch "/api/orders/#{order.id}/decline_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["state"]).to eq("canceled")
+    end
+
+    it "accepts an optional reason" do
+      patch "/api/orders/#{order.id}/decline_proposal",
+        params: { reason: "Time doesn't work" },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["cancel_reason"]).to eq("Time doesn't work")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/decline_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
 end
diff --git a/affordance_order/spec/services/orders/accept_proposal_service_spec.rb b/affordance_order/spec/services/orders/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..384c070
--- /dev/null
+++ b/affordance_order/spec/services/orders/accept_proposal_service_spec.rb
@@ -0,0 +1,63 @@
+require "rails_helper"
+
+RSpec.describe Orders::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:order) do
+    create(:order, :provider_proposed, client: client, provider: provider,
+      proposed_scheduled_at: proposed_time, proposed_duration_minutes: 90)
+  end
+
+  describe "#call" do
+    it "accepts the proposal and confirms the order" do
+      result = described_class.new(order: order, client: client).call
+
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("confirmed")
+    end
+
+    it "updates scheduled_at to the proposed time" do
+      described_class.new(order: order, client: client).call
+
+      expect(order.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "updates duration when proposed" do
+      described_class.new(order: order, client: client).call
+
+      expect(order.reload.duration_minutes).to eq(90)
+    end
+
+    it "keeps original duration when no proposed duration" do
+      order.update!(proposed_duration_minutes: nil)
+      original_duration = order.duration_minutes
+
+      described_class.new(order: order, client: client).call
+
+      expect(order.reload.duration_minutes).to eq(original_duration)
+    end
+
+    it "notifies the provider" do
+      described_class.new(order: order, client: client).call
+
+      expect(read_notification_log).to include("event=proposal_accepted")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(order: order, client: other_client).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails for non-proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept proposal")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/decline_proposal_service_spec.rb b/affordance_order/spec/services/orders/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..5641009
--- /dev/null
+++ b/affordance_order/spec/services/orders/decline_proposal_service_spec.rb
@@ -0,0 +1,50 @@
+require "rails_helper"
+
+RSpec.describe Orders::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:order) { create(:order, :provider_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    it "declines the proposal and cancels the order" do
+      result = described_class.new(order: order, client: client).call
+
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("canceled")
+    end
+
+    it "sets a default cancel reason when none given" do
+      described_class.new(order: order, client: client).call
+
+      expect(order.reload.cancel_reason).to eq("Declined counter-proposal")
+    end
+
+    it "uses provided reason" do
+      described_class.new(order: order, client: client, reason: "Time doesn't work").call
+
+      expect(order.reload.cancel_reason).to eq("Time doesn't work")
+    end
+
+    it "notifies the provider" do
+      described_class.new(order: order, client: client).call
+
+      expect(read_notification_log).to include("event=proposal_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(order: order, client: other_client).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails for non-proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline proposal")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/propose_new_time_service_spec.rb b/affordance_order/spec/services/orders/propose_new_time_service_spec.rb
new file mode 100644
index 0000000..70bdbe6
--- /dev/null
+++ b/affordance_order/spec/services/orders/propose_new_time_service_spec.rb
@@ -0,0 +1,73 @@
+require "rails_helper"
+
+RSpec.describe Orders::ProposeNewTimeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:order) { create(:order, client: client, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "proposes a new time for a pending order" do
+      result = described_class.new(
+        order: order, provider: provider,
+        proposed_scheduled_at: proposed_time
+      ).call
+
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("provider_proposed")
+      expect(order.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "optionally sets proposed duration" do
+      result = described_class.new(
+        order: order, provider: provider,
+        proposed_scheduled_at: proposed_time,
+        proposed_duration_minutes: 90
+      ).call
+
+      expect(result[:success]).to be true
+      expect(order.reload.proposed_duration_minutes).to eq(90)
+    end
+
+    it "notifies the client" do
+      described_class.new(
+        order: order, provider: provider,
+        proposed_scheduled_at: proposed_time
+      ).call
+
+      expect(read_notification_log).to include("event=new_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(
+        order: order, provider: other_provider,
+        proposed_scheduled_at: proposed_time
+      ).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails without proposed time" do
+      result = described_class.new(
+        order: order, provider: provider,
+        proposed_scheduled_at: nil
+      ).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails for non-pending order" do
+      order.update!(state: "confirmed")
+      result = described_class.new(
+        order: order, provider: provider,
+        proposed_scheduled_at: proposed_time
+      ).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose new time")
+    end
+  end
+end
```
