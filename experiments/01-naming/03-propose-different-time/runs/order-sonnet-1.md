# Experiment: 03-propose-different-time
# App: order | Model: sonnet | Run: 1
# Branch: experiment/03-propose-different-time/order/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**New state: `counter_proposed`**

**Flow:**
1. Client creates an order (pending)
2. Provider calls `PATCH /api/orders/:id/propose_time` with `proposed_scheduled_at` (required) and optional `note` → order moves to `counter_proposed`
3. Client sees the counter-proposal (new fields `counter_proposed_scheduled_at`, `counter_proposal_note` in the response) and either:
   - `PATCH /api/orders/:id/accept_counter_proposal` → order moves to `confirmed`, `scheduled_at` updated to the proposed time
   - `PATCH /api/orders/:id/decline_counter_proposal` → order moves to `canceled`

**Files changed:**
- `db/migrate/...` — adds `counter_proposed_scheduled_at` and `counter_proposal_note` columns
- `app/models/order.rb` — new state and AASM events
- `app/services/orders/propose_time_service.rb` — provider action
- `app/services/orders/accept_counter_proposal_service.rb` — client accepts
- `app/services/orders/decline_counter_proposal_service.rb` — client declines
- `app/controllers/api/orders_controller.rb` — three new actions, new fields in JSON
- `config/routes.rb` — three new routes
- `spec/factories/orders.rb` — `:counter_proposed` trait
- `spec/requests/api/orders_spec.rb` — 10 new specs (all passing, 276 total)

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..832ded3 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_time, :accept_counter_proposal, :decline_counter_proposal]
 
     def index
       orders = scoped_orders
@@ -90,6 +90,39 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_scheduled_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Orders::ProposeTimeService.new(
+        order: @order,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at],
+        note: params[:note]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter_proposal
+      client = current_client!
+      return if performed?
+
+      result = Orders::AcceptCounterProposalService.new(order: @order, client: client).call
+      handle_service_result(result)
+    end
+
+    def decline_counter_proposal
+      client = current_client!
+      return if performed?
+
+      result = Orders::DeclineCounterProposalService.new(order: @order, client: client).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_order
@@ -141,6 +174,8 @@ def order_detail_json(order)
         currency: order.currency,
         cancel_reason: order.cancel_reason,
         reject_reason: order.reject_reason,
+        counter_proposed_scheduled_at: order.counter_proposed_scheduled_at,
+        counter_proposal_note: order.counter_proposal_note,
         started_at: order.started_at,
         completed_at: order.completed_at,
         client_id: order.client_id,
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..4dca058 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -13,6 +13,7 @@ class Order < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :counter_proposed_scheduled_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -29,6 +30,7 @@ class Order < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :counter_proposed
     state :confirmed
     state :in_progress
     state :completed
@@ -39,6 +41,18 @@ class Order < ApplicationRecord
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_time do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_counter_proposal do
+      transitions from: :counter_proposed, to: :confirmed
+    end
+
+    event :decline_counter_proposal do
+      transitions from: :counter_proposed, to: :canceled
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
diff --git a/affordance_order/app/services/orders/accept_counter_proposal_service.rb b/affordance_order/app/services/orders/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..116cc7b
--- /dev/null
+++ b/affordance_order/app/services/orders/accept_counter_proposal_service.rb
@@ -0,0 +1,26 @@
+module Orders
+  class AcceptCounterProposalService
+    def initialize(order:, client:)
+      @order = order
+      @client = client
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+
+      @order.scheduled_at = @order.counter_proposed_scheduled_at
+      @order.accept_counter_proposal!
+
+      NotificationService.notify(@order.provider, :counter_proposal_accepted, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter-proposal for order in #{@order.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_order/app/services/orders/decline_counter_proposal_service.rb b/affordance_order/app/services/orders/decline_counter_proposal_service.rb
new file mode 100644
index 0000000..0850242
--- /dev/null
+++ b/affordance_order/app/services/orders/decline_counter_proposal_service.rb
@@ -0,0 +1,26 @@
+module Orders
+  class DeclineCounterProposalService
+    def initialize(order:, client:)
+      @order = order
+      @client = client
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+
+      @order.cancel_reason = "Counter-proposal declined by client"
+      @order.decline_counter_proposal!
+
+      NotificationService.notify(@order.provider, :counter_proposal_declined, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot decline counter-proposal for order in #{@order.state} state")
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
index 0000000..0d5fb2f
--- /dev/null
+++ b/affordance_order/app/services/orders/propose_time_service.rb
@@ -0,0 +1,30 @@
+module Orders
+  class ProposeTimeService
+    def initialize(order:, provider:, proposed_scheduled_at:, note: nil)
+      @order = order
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+      @note = note
+    end
+
+    def call
+      return error("Not your order") unless @order.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @order.counter_proposed_scheduled_at = @proposed_scheduled_at
+      @order.counter_proposal_note = @note
+      @order.propose_time!
+
+      NotificationService.notify(@order.client, :order_time_proposed, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot propose a different time for order in #{@order.state} state")
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
index 9c38c15..f7737f6 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -17,6 +17,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :propose_time
+        patch :accept_counter_proposal
+        patch :decline_counter_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_order/db/migrate/20260407110839_add_counter_proposal_to_orders.rb b/affordance_order/db/migrate/20260407110839_add_counter_proposal_to_orders.rb
new file mode 100644
index 0000000..158fc39
--- /dev/null
+++ b/affordance_order/db/migrate/20260407110839_add_counter_proposal_to_orders.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :counter_proposed_scheduled_at, :datetime
+    add_column :orders, :counter_proposal_note, :text
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..5ad71c4 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_110839) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -41,11 +41,14 @@
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
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_order/spec/factories/orders.rb b/affordance_order/spec/factories/orders.rb
index 81b3def..bf6b5fd 100644
--- a/affordance_order/spec/factories/orders.rb
+++ b/affordance_order/spec/factories/orders.rb
@@ -34,6 +34,12 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :counter_proposed do
+      state { "counter_proposed" }
+      counter_proposed_scheduled_at { 5.days.from_now }
+      counter_proposal_note { "I can only do Thursday instead" }
+    end
+
     trait :with_payment do
       after(:create) do |order|
         create(:payment, order: order, amount_cents: order.amount_cents, currency: order.currency)
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..e96344a 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -180,4 +180,92 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "PATCH /api/orders/:id/propose_time" do
+    let(:order) { create(:order, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "allows provider to propose a different time" do
+      patch "/api/orders/#{order.id}/propose_time",
+            params: { proposed_scheduled_at: proposed_time, note: "How about Thursday?" },
+            headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("counter_proposed")
+      expect(body["counter_proposed_scheduled_at"]).to be_present
+      expect(body["counter_proposal_note"]).to eq("How about Thursday?")
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/orders/#{order.id}/propose_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/orders/#{order.id}/propose_time",
+            params: { proposed_scheduled_at: proposed_time },
+            headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when wrong provider tries to propose" do
+      other_provider = create(:provider)
+      patch "/api/orders/#{order.id}/propose_time",
+            params: { proposed_scheduled_at: proposed_time },
+            headers: auth_headers(other_provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns error when order is not pending" do
+      confirmed_order = create(:order, :confirmed, client: client, provider: provider)
+      patch "/api/orders/#{confirmed_order.id}/propose_time",
+            params: { proposed_scheduled_at: proposed_time },
+            headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/accept_counter_proposal" do
+    let(:order) { create(:order, :counter_proposed, client: client, provider: provider) }
+
+    it "allows client to accept a counter-proposal" do
+      patch "/api/orders/#{order.id}/accept_counter_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+      expect(body["scheduled_at"]).to eq(order.counter_proposed_scheduled_at.iso8601(3))
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/accept_counter_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when order is not counter_proposed" do
+      pending_order = create(:order, client: client, provider: provider)
+      patch "/api/orders/#{pending_order.id}/accept_counter_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/decline_counter_proposal" do
+    let(:order) { create(:order, :counter_proposed, client: client, provider: provider) }
+
+    it "allows client to decline a counter-proposal" do
+      patch "/api/orders/#{order.id}/decline_counter_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      expect(JSON.parse(response.body)["state"]).to eq("canceled")
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/decline_counter_proposal", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when order is not counter_proposed" do
+      pending_order = create(:order, client: client, provider: provider)
+      patch "/api/orders/#{pending_order.id}/decline_counter_proposal", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
```
