# Experiment: 03-propose-different-time
# App: order | Model: sonnet | Run: 2
# Branch: experiment/03-propose-different-time/order/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**New state:** `counter_proposed`

**New AASM events on `Order`:**
- `propose_time`: `pending` → `counter_proposed`
- `accept_proposal`: `counter_proposed` → `confirmed` (copies `proposed_at`/`proposed_duration_minutes` onto the order)
- `decline_proposal`: `counter_proposed` → `canceled`

**New columns:** `proposed_at` (datetime), `proposed_duration_minutes` (integer)

**New services:** `ProposeTimeService`, `AcceptProposalService`, `DeclineProposalService`

**New API endpoints:**
- `PATCH /api/orders/:id/propose_time` — provider only, requires `proposed_at`, optional `proposed_duration_minutes`
- `PATCH /api/orders/:id/accept_proposal` — client only
- `PATCH /api/orders/:id/decline_proposal` — client only, requires `reason`

All 89 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..2f34454 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_time, :accept_proposal, :decline_proposal]
 
     def index
       orders = scoped_orders
@@ -90,6 +90,47 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Orders::ProposeTimeService.new(
+        order: @order,
+        provider: provider,
+        proposed_at: params[:proposed_at],
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
+      if params[:reason].blank?
+        return render_unprocessable(["Reason is required"])
+      end
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
@@ -141,6 +182,8 @@ def order_detail_json(order)
         currency: order.currency,
         cancel_reason: order.cancel_reason,
         reject_reason: order.reject_reason,
+        proposed_at: order.proposed_at,
+        proposed_duration_minutes: order.proposed_duration_minutes,
         started_at: order.started_at,
         completed_at: order.completed_at,
         client_id: order.client_id,
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..e8e2912 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -13,6 +13,7 @@ class Order < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -29,6 +30,7 @@ class Order < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :counter_proposed
     state :confirmed
     state :in_progress
     state :completed
@@ -39,6 +41,21 @@ class Order < ApplicationRecord
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_time do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :counter_proposed, to: :confirmed
+      after do
+        update!(scheduled_at: proposed_at, duration_minutes: proposed_duration_minutes || duration_minutes)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :counter_proposed, to: :canceled
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
diff --git a/affordance_order/app/services/orders/accept_proposal_service.rb b/affordance_order/app/services/orders/accept_proposal_service.rb
new file mode 100644
index 0000000..48b5f22
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
+      NotificationService.notify(@order.provider, :order_proposal_accepted, order_id: @order.id)
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
index 0000000..5ae2bea
--- /dev/null
+++ b/affordance_order/app/services/orders/decline_proposal_service.rb
@@ -0,0 +1,28 @@
+module Orders
+  class DeclineProposalService
+    def initialize(order:, client:, reason:)
+      @order = order
+      @client = client
+      @reason = reason
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+      return error("Reason is required") if @reason.blank?
+
+      @order.cancel_reason = @reason
+      @order.decline_proposal!
+
+      NotificationService.notify(@order.provider, :order_proposal_declined, order_id: @order.id)
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
diff --git a/affordance_order/app/services/orders/propose_time_service.rb b/affordance_order/app/services/orders/propose_time_service.rb
new file mode 100644
index 0000000..4c57b6d
--- /dev/null
+++ b/affordance_order/app/services/orders/propose_time_service.rb
@@ -0,0 +1,30 @@
+module Orders
+  class ProposeTimeService
+    def initialize(order:, provider:, proposed_at:, proposed_duration_minutes: nil)
+      @order = order
+      @provider = provider
+      @proposed_at = proposed_at
+      @proposed_duration_minutes = proposed_duration_minutes
+    end
+
+    def call
+      return error("Not your order") unless @order.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_at.blank?
+
+      @order.proposed_at = @proposed_at
+      @order.proposed_duration_minutes = @proposed_duration_minutes
+      @order.propose_time!
+
+      NotificationService.notify(@order.client, :order_time_proposed, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot propose time for order in #{@order.state} state")
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
index 9c38c15..7952e8f 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -17,6 +17,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :propose_time
+        patch :accept_proposal
+        patch :decline_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_order/db/migrate/20260407111252_add_proposed_time_to_orders.rb b/affordance_order/db/migrate/20260407111252_add_proposed_time_to_orders.rb
new file mode 100644
index 0000000..16aa682
--- /dev/null
+++ b/affordance_order/db/migrate/20260407111252_add_proposed_time_to_orders.rb
@@ -0,0 +1,6 @@
+class AddProposedTimeToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :proposed_at, :datetime
+    add_column :orders, :proposed_duration_minutes, :integer
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..919d1c2 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_111252) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -41,11 +41,16 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.text "counter_proposal_note"
+    t.datetime "counter_proposed_scheduled_at"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_at"
+    t.integer "proposed_duration_minutes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_order/spec/factories/orders.rb b/affordance_order/spec/factories/orders.rb
index 81b3def..97f4a31 100644
--- a/affordance_order/spec/factories/orders.rb
+++ b/affordance_order/spec/factories/orders.rb
@@ -46,6 +46,11 @@
       end
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      proposed_at { 5.days.from_now }
+    end
+
     trait :scheduled_tomorrow do
       scheduled_at { 1.day.from_now }
     end
diff --git a/affordance_order/spec/models/order_spec.rb b/affordance_order/spec/models/order_spec.rb
index 6686df0..12688f8 100644
--- a/affordance_order/spec/models/order_spec.rb
+++ b/affordance_order/spec/models/order_spec.rb
@@ -140,6 +140,61 @@
         expect { order.reject! }.to raise_error(AASM::InvalidTransition)
       end
     end
+
+    describe "propose_time event" do
+      it "transitions from pending to counter_proposed" do
+        order.proposed_at = 5.days.from_now
+        order.propose_time!
+        expect(order).to be_counter_proposed
+      end
+
+      it "cannot propose from confirmed" do
+        order.confirm!
+        expect { order.propose_time! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_proposal event" do
+      before do
+        order.proposed_at = 5.days.from_now
+        order.proposed_duration_minutes = 90
+        order.propose_time!
+      end
+
+      it "transitions from counter_proposed to confirmed" do
+        order.accept_proposal!
+        expect(order).to be_confirmed
+      end
+
+      it "updates scheduled_at to proposed_at" do
+        proposed = order.proposed_at
+        order.accept_proposal!
+        expect(order.reload.scheduled_at).to be_within(1.second).of(proposed)
+      end
+
+      it "updates duration_minutes to proposed_duration_minutes when present" do
+        order.accept_proposal!
+        expect(order.reload.duration_minutes).to eq(90)
+      end
+    end
+
+    describe "decline_proposal event" do
+      before do
+        order.proposed_at = 5.days.from_now
+        order.propose_time!
+        order.update!(cancel_reason: "Proposed time does not work")
+      end
+
+      it "transitions from counter_proposed to canceled" do
+        order.decline_proposal!
+        expect(order).to be_canceled
+      end
+
+      it "cannot decline from pending" do
+        pending_order = create(:order)
+        expect { pending_order.decline_proposal! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
   end
 
   describe "scopes" do
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..ed4207b 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -180,4 +180,102 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/orders/:id/propose_time" do
+    let(:order) { create(:order, client: client, provider: provider) }
+    let(:new_time) { 5.days.from_now.iso8601 }
+
+    it "allows provider to propose a different time" do
+      patch "/api/orders/#{order.id}/propose_time",
+        params: { proposed_at: new_time },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("counter_proposed")
+      expect(body["proposed_at"]).to be_present
+    end
+
+    it "allows provider to include proposed_duration_minutes" do
+      patch "/api/orders/#{order.id}/propose_time",
+        params: { proposed_at: new_time, proposed_duration_minutes: 90 },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["proposed_duration_minutes"]).to eq(90)
+    end
+
+    it "returns error without proposed_at" do
+      patch "/api/orders/#{order.id}/propose_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/orders/#{order.id}/propose_time",
+        params: { proposed_at: new_time },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when wrong provider tries to propose" do
+      other_provider = create(:provider)
+      patch "/api/orders/#{order.id}/propose_time",
+        params: { proposed_at: new_time },
+        headers: auth_headers(other_provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/accept_proposal" do
+    let(:proposed_time) { 5.days.from_now }
+    let(:order) { create(:order, :counter_proposed, client: client, provider: provider, proposed_at: proposed_time) }
+
+    it "allows client to accept the counter-proposal" do
+      patch "/api/orders/#{order.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+    end
+
+    it "updates scheduled_at to proposed_at" do
+      patch "/api/orders/#{order.id}/accept_proposal", headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      expect(Time.parse(body["scheduled_at"])).to be_within(1.second).of(proposed_time)
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/accept_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when wrong client tries to accept" do
+      other_client = create(:client)
+      patch "/api/orders/#{order.id}/accept_proposal", headers: auth_headers(other_client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/decline_proposal" do
+    let(:order) { create(:order, :counter_proposed, client: client, provider: provider) }
+
+    it "allows client to decline the counter-proposal" do
+      patch "/api/orders/#{order.id}/decline_proposal",
+        params: { reason: "Proposed time does not work for me" },
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("canceled")
+    end
+
+    it "returns error without reason" do
+      patch "/api/orders/#{order.id}/decline_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/decline_proposal",
+        params: { reason: "test" },
+        headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
 end
diff --git a/affordance_order/spec/services/orders/accept_proposal_service_spec.rb b/affordance_order/spec/services/orders/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..6005965
--- /dev/null
+++ b/affordance_order/spec/services/orders/accept_proposal_service_spec.rb
@@ -0,0 +1,40 @@
+require "rails_helper"
+
+RSpec.describe Orders::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:order) { create(:order, :counter_proposed, client: client, provider: provider, proposed_at: proposed_time) }
+
+  describe "#call" do
+    it "transitions order to confirmed" do
+      result = described_class.new(order: order, client: client).call
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("confirmed")
+    end
+
+    it "updates scheduled_at to proposed_at" do
+      described_class.new(order: order, client: client).call
+      expect(order.reload.scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "notifies the provider" do
+      described_class.new(order: order, client: client).call
+      expect(read_notification_log).to include("event=order_proposal_accepted")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(order: order, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails for non-counter_proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept proposal")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/decline_proposal_service_spec.rb b/affordance_order/spec/services/orders/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..d8d3a64
--- /dev/null
+++ b/affordance_order/spec/services/orders/decline_proposal_service_spec.rb
@@ -0,0 +1,45 @@
+require "rails_helper"
+
+RSpec.describe Orders::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:order) { create(:order, :counter_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    it "transitions order to canceled" do
+      result = described_class.new(order: order, client: client, reason: "Time does not work").call
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("canceled")
+    end
+
+    it "stores the cancel_reason" do
+      described_class.new(order: order, client: client, reason: "Time does not work").call
+      expect(order.reload.cancel_reason).to eq("Time does not work")
+    end
+
+    it "notifies the provider" do
+      described_class.new(order: order, client: client, reason: "Time does not work").call
+      expect(read_notification_log).to include("event=order_proposal_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(order: order, client: other_client, reason: "test").call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails without reason" do
+      result = described_class.new(order: order, client: client, reason: "").call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Reason is required")
+    end
+
+    it "fails for non-counter_proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client, reason: "test").call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline proposal")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/propose_time_service_spec.rb b/affordance_order/spec/services/orders/propose_time_service_spec.rb
new file mode 100644
index 0000000..47b75a9
--- /dev/null
+++ b/affordance_order/spec/services/orders/propose_time_service_spec.rb
@@ -0,0 +1,51 @@
+require "rails_helper"
+
+RSpec.describe Orders::ProposeTimeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:order) { create(:order, client: client, provider: provider) }
+  let(:new_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "transitions order to counter_proposed" do
+      result = described_class.new(order: order, provider: provider, proposed_at: new_time).call
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("counter_proposed")
+    end
+
+    it "stores the proposed_at time" do
+      described_class.new(order: order, provider: provider, proposed_at: new_time).call
+      expect(order.reload.proposed_at).to be_within(1.second).of(new_time)
+    end
+
+    it "stores proposed_duration_minutes when provided" do
+      described_class.new(order: order, provider: provider, proposed_at: new_time, proposed_duration_minutes: 90).call
+      expect(order.reload.proposed_duration_minutes).to eq(90)
+    end
+
+    it "notifies the client" do
+      described_class.new(order: order, provider: provider, proposed_at: new_time).call
+      expect(read_notification_log).to include("event=order_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(order: order, provider: other_provider, proposed_at: new_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails without proposed_at" do
+      result = described_class.new(order: order, provider: provider, proposed_at: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails for non-pending order" do
+      order.update!(state: "confirmed")
+      result = described_class.new(order: order, provider: provider, proposed_at: new_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose time")
+    end
+  end
+end
```
