# Experiment: 03-propose-different-time
# App: order | Model: opus | Run: 3
# Branch: experiment/03-propose-different-time/order/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**New state:** `provider_proposed` — entered when a provider proposes a different time instead of accepting/rejecting.

**Flow:**
1. **Provider calls `PATCH /api/orders/:id/propose_new_time`** with `proposed_scheduled_at` — order moves from `pending` → `provider_proposed`, client is notified
2. **Client calls `PATCH /api/orders/:id/accept_proposal`** — `scheduled_at` is updated to the proposed time, order moves to `confirmed`, provider is notified
3. **Client calls `PATCH /api/orders/:id/decline_proposal`** — order returns to `pending`, `proposed_scheduled_at` is cleared, provider is notified

**Files changed:**
- Migration adding `proposed_scheduled_at` column to orders
- `Order` model — new state + 3 AASM events, cancel also allowed from `provider_proposed`
- 3 new service classes following existing patterns
- Controller actions + routes
- `proposed_scheduled_at` included in order detail JSON
- Full specs: model, service, and request (all 289 tests pass)

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..748b098 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_new_time, :accept_proposal, :decline_proposal]
 
     def index
       orders = scoped_orders
@@ -90,6 +90,38 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_new_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_scheduled_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Orders::ProposeNewTimeService.new(
+        order: @order,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at]
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
+      result = Orders::DeclineProposalService.new(order: @order, client: client).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_order
@@ -139,6 +171,7 @@ def order_detail_json(order)
         notes: order.notes,
         amount_cents: order.amount_cents,
         currency: order.currency,
+        proposed_scheduled_at: order.proposed_scheduled_at,
         cancel_reason: order.cancel_reason,
         reject_reason: order.reject_reason,
         started_at: order.started_at,
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..5b33553 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -29,6 +29,7 @@ class Order < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :provider_proposed
     state :confirmed
     state :in_progress
     state :completed
@@ -39,6 +40,21 @@ class Order < ApplicationRecord
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_new_time do
+      transitions from: :pending, to: :provider_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :provider_proposed, to: :confirmed
+    end
+
+    event :decline_proposal do
+      transitions from: :provider_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil)
+      end
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
@@ -54,7 +70,7 @@ class Order < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :confirmed], to: :canceled
+      transitions from: [:pending, :confirmed, :provider_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/affordance_order/app/services/orders/accept_proposal_service.rb b/affordance_order/app/services/orders/accept_proposal_service.rb
new file mode 100644
index 0000000..918466c
--- /dev/null
+++ b/affordance_order/app/services/orders/accept_proposal_service.rb
@@ -0,0 +1,27 @@
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
+      @order.scheduled_at = @order.proposed_scheduled_at
+      @order.proposed_scheduled_at = nil
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
index 0000000..0fcb064
--- /dev/null
+++ b/affordance_order/app/services/orders/decline_proposal_service.rb
@@ -0,0 +1,25 @@
+module Orders
+  class DeclineProposalService
+    def initialize(order:, client:)
+      @order = order
+      @client = client
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+
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
diff --git a/affordance_order/app/services/orders/propose_new_time_service.rb b/affordance_order/app/services/orders/propose_new_time_service.rb
new file mode 100644
index 0000000..3283b0d
--- /dev/null
+++ b/affordance_order/app/services/orders/propose_new_time_service.rb
@@ -0,0 +1,28 @@
+module Orders
+  class ProposeNewTimeService
+    def initialize(order:, provider:, proposed_scheduled_at:)
+      @order = order
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+    end
+
+    def call
+      return error("Not your order") unless @order.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @order.proposed_scheduled_at = @proposed_scheduled_at
+      @order.propose_new_time!
+
+      NotificationService.notify(@order.client, :order_time_proposed, order_id: @order.id, proposed_scheduled_at: @proposed_scheduled_at)
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
diff --git a/affordance_order/db/migrate/20260407114035_add_proposed_scheduled_at_to_orders.rb b/affordance_order/db/migrate/20260407114035_add_proposed_scheduled_at_to_orders.rb
new file mode 100644
index 0000000..aaa087d
--- /dev/null
+++ b/affordance_order/db/migrate/20260407114035_add_proposed_scheduled_at_to_orders.rb
@@ -0,0 +1,5 @@
+class AddProposedScheduledAtToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :proposed_scheduled_at, :datetime unless column_exists?(:orders, :proposed_scheduled_at)
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..542958e 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_114035) do
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
index 81b3def..7f40665 100644
--- a/affordance_order/spec/factories/orders.rb
+++ b/affordance_order/spec/factories/orders.rb
@@ -34,6 +34,11 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :provider_proposed do
+      state { "provider_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :with_payment do
       after(:create) do |order|
         create(:payment, order: order, amount_cents: order.amount_cents, currency: order.currency)
diff --git a/affordance_order/spec/models/order_spec.rb b/affordance_order/spec/models/order_spec.rb
index 6686df0..280748d 100644
--- a/affordance_order/spec/models/order_spec.rb
+++ b/affordance_order/spec/models/order_spec.rb
@@ -120,6 +120,38 @@
       end
     end
 
+    describe "propose_new_time event" do
+      it "transitions from pending to provider_proposed" do
+        order.propose_new_time!
+        expect(order).to be_provider_proposed
+      end
+
+      it "cannot propose from confirmed" do
+        order.confirm!
+        expect { order.propose_new_time! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_proposal event" do
+      before { order.propose_new_time! }
+
+      it "transitions from provider_proposed to confirmed" do
+        order.accept_proposal!
+        expect(order).to be_confirmed
+      end
+    end
+
+    describe "decline_proposal event" do
+      before { order.propose_new_time! }
+
+      it "transitions from provider_proposed to pending" do
+        order.update!(proposed_scheduled_at: 5.days.from_now)
+        order.decline_proposal!
+        expect(order).to be_pending
+        expect(order.reload.proposed_scheduled_at).to be_nil
+      end
+    end
+
     describe "reject event" do
       it "transitions from confirmed to rejected" do
         order.confirm!
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..753e54e 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -166,6 +166,62 @@
     end
   end
 
+  describe "PATCH /api/orders/:id/propose_new_time" do
+    let(:order) { create(:order, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "proposes a new time as provider" do
+      patch "/api/orders/#{order.id}/propose_new_time", params: { proposed_scheduled_at: proposed_time }, headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("provider_proposed")
+      expect(body["proposed_scheduled_at"]).to be_present
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/orders/#{order.id}/propose_new_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/orders/#{order.id}/propose_new_time", params: { proposed_scheduled_at: proposed_time }, headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/accept_proposal" do
+    let(:order) { create(:order, :provider_proposed, client: client, provider: provider) }
+
+    it "accepts proposal as client" do
+      patch "/api/orders/#{order.id}/accept_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+      expect(body["proposed_scheduled_at"]).to be_nil
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
+    it "declines proposal as client" do
+      patch "/api/orders/#{order.id}/decline_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/decline_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
   describe "PATCH /api/orders/:id/reject" do
     let(:order) { create(:order, :confirmed, client: client, provider: provider) }
 
diff --git a/affordance_order/spec/services/orders/accept_proposal_service_spec.rb b/affordance_order/spec/services/orders/accept_proposal_service_spec.rb
new file mode 100644
index 0000000..c4a910f
--- /dev/null
+++ b/affordance_order/spec/services/orders/accept_proposal_service_spec.rb
@@ -0,0 +1,38 @@
+require "rails_helper"
+
+RSpec.describe Orders::AcceptProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:order) { create(:order, :provider_proposed, client: client, provider: provider, proposed_scheduled_at: proposed_time) }
+
+  describe "#call" do
+    it "accepts the proposal and updates scheduled_at" do
+      result = described_class.new(order: order, client: client).call
+      expect(result[:success]).to be true
+      order.reload
+      expect(order.state).to eq("confirmed")
+      expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
+      expect(order.proposed_scheduled_at).to be_nil
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
+    it "fails for non-provider_proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept proposal")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/decline_proposal_service_spec.rb b/affordance_order/spec/services/orders/decline_proposal_service_spec.rb
new file mode 100644
index 0000000..fa6188e
--- /dev/null
+++ b/affordance_order/spec/services/orders/decline_proposal_service_spec.rb
@@ -0,0 +1,36 @@
+require "rails_helper"
+
+RSpec.describe Orders::DeclineProposalService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:order) { create(:order, :provider_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    it "declines the proposal and returns to pending" do
+      result = described_class.new(order: order, client: client).call
+      expect(result[:success]).to be true
+      order.reload
+      expect(order.state).to eq("pending")
+      expect(order.proposed_scheduled_at).to be_nil
+    end
+
+    it "notifies the provider" do
+      described_class.new(order: order, client: client).call
+      expect(read_notification_log).to include("event=order_proposal_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(order: order, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails for non-provider_proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline proposal")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/propose_new_time_service_spec.rb b/affordance_order/spec/services/orders/propose_new_time_service_spec.rb
new file mode 100644
index 0000000..cee47c7
--- /dev/null
+++ b/affordance_order/spec/services/orders/propose_new_time_service_spec.rb
@@ -0,0 +1,42 @@
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
+      result = described_class.new(order: order, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("provider_proposed")
+      expect(order.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "notifies the client" do
+      described_class.new(order: order, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(read_notification_log).to include("event=order_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(order: order, provider: other_provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails without proposed time" do
+      result = described_class.new(order: order, provider: provider, proposed_scheduled_at: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails for non-pending order" do
+      order.update!(state: "confirmed")
+      result = described_class.new(order: order, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose new time")
+    end
+  end
+end
```
