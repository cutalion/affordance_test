# Experiment: 03-propose-different-time
# App: order | Model: sonnet | Run: 3
# Branch: experiment/03-propose-different-time/order/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**New state: `time_proposed`** — sits between `pending`/`confirmed` and resolution.

**Provider actions:**
- `PATCH /api/orders/:id/propose_time` — params: `proposed_time` (ISO8601), `reason`. Transitions from `pending` or `confirmed` → `time_proposed`. Notifies client.

**Client actions:**
- `PATCH /api/orders/:id/accept_proposal` — updates `scheduled_at` to the proposed time, transitions to `confirmed`. Notifies provider.
- `PATCH /api/orders/:id/decline_proposal` — transitions to `rejected` (with payment refund if applicable). Notifies provider.

**Supporting changes:**
- Migration adds `proposed_time` (datetime) and `proposal_reason` (text) columns
- `order_detail_json` exposes the new fields
- Client can still cancel a `time_proposed` order
- 3 new mailer methods for notifications
- All 265 existing tests pass

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..c3ee796 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_time, :accept_proposal, :decline_proposal]
 
     def index
       orders = scoped_orders
@@ -90,6 +90,46 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_time].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      if params[:reason].blank?
+        return render_unprocessable(["Reason is required"])
+      end
+
+      proposed_time = Time.zone.parse(params[:proposed_time]) rescue nil
+      return render_unprocessable(["Invalid proposed time format"]) unless proposed_time
+
+      result = Orders::ProposeTimeService.new(
+        order: @order,
+        provider: provider,
+        proposed_time: proposed_time,
+        reason: params[:reason]
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
@@ -141,6 +181,8 @@ def order_detail_json(order)
         currency: order.currency,
         cancel_reason: order.cancel_reason,
         reject_reason: order.reject_reason,
+        proposed_time: order.proposed_time,
+        proposal_reason: order.proposal_reason,
         started_at: order.started_at,
         completed_at: order.completed_at,
         client_id: order.client_id,
diff --git a/affordance_order/app/mailers/order_mailer.rb b/affordance_order/app/mailers/order_mailer.rb
index 428fd89..bb1aa16 100644
--- a/affordance_order/app/mailers/order_mailer.rb
+++ b/affordance_order/app/mailers/order_mailer.rb
@@ -35,6 +35,24 @@ def order_rejected(recipient, payload)
     mail(to: recipient.email, subject: "Order ##{@order_id} rejected")
   end
 
+  def time_proposed(recipient, payload)
+    @recipient = recipient
+    @order_id = payload[:order_id]
+    mail(to: recipient.email, subject: "Provider proposed a new time for order ##{@order_id}")
+  end
+
+  def proposal_accepted(recipient, payload)
+    @recipient = recipient
+    @order_id = payload[:order_id]
+    mail(to: recipient.email, subject: "Client accepted your time proposal for order ##{@order_id}")
+  end
+
+  def proposal_declined(recipient, payload)
+    @recipient = recipient
+    @order_id = payload[:order_id]
+    mail(to: recipient.email, subject: "Client declined your time proposal for order ##{@order_id}")
+  end
+
   def review_reminder(recipient, payload)
     @recipient = recipient
     @order_id = payload[:order_id]
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..bc90566 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -13,6 +13,8 @@ class Order < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_time, presence: true, if: -> { time_proposed? }
+  validates :proposal_reason, presence: true, if: -> { time_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -30,6 +32,7 @@ class Order < ApplicationRecord
   aasm column: :state do
     state :pending, initial: true
     state :confirmed
+    state :time_proposed
     state :in_progress
     state :completed
     state :canceled
@@ -39,6 +42,21 @@ class Order < ApplicationRecord
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_time do
+      transitions from: [:pending, :confirmed], to: :time_proposed
+    end
+
+    event :accept_proposal do
+      transitions from: :time_proposed, to: :confirmed
+      after do
+        update!(scheduled_at: proposed_time, proposed_time: nil, proposal_reason: nil)
+      end
+    end
+
+    event :decline_proposal do
+      transitions from: :time_proposed, to: :rejected
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
@@ -54,7 +72,7 @@ class Order < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :confirmed], to: :canceled
+      transitions from: [:pending, :confirmed, :time_proposed], to: :canceled
     end
 
     event :reject do
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
index 0000000..3192d4f
--- /dev/null
+++ b/affordance_order/app/services/orders/decline_proposal_service.rb
@@ -0,0 +1,30 @@
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
+      @order.reject_reason = "Client declined proposed time"
+      @order.decline_proposal!
+
+      if @order.payment && %w[held charged].include?(@order.payment.status)
+        PaymentGateway.refund(@order.payment)
+      end
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
diff --git a/affordance_order/app/services/orders/propose_time_service.rb b/affordance_order/app/services/orders/propose_time_service.rb
new file mode 100644
index 0000000..b26ed14
--- /dev/null
+++ b/affordance_order/app/services/orders/propose_time_service.rb
@@ -0,0 +1,32 @@
+module Orders
+  class ProposeTimeService
+    def initialize(order:, provider:, proposed_time:, reason:)
+      @order = order
+      @provider = provider
+      @proposed_time = proposed_time
+      @reason = reason
+    end
+
+    def call
+      return error("Not your order") unless @order.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_time.blank?
+      return error("Reason is required") if @reason.blank?
+      return error("Proposed time must be in the future") if @proposed_time <= Time.current
+
+      @order.proposed_time = @proposed_time
+      @order.proposal_reason = @reason
+      @order.propose_time!
+
+      NotificationService.notify(@order.client, :time_proposed, order_id: @order.id)
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
diff --git a/affordance_order/db/migrate/20260407111859_add_proposed_time_to_orders.rb b/affordance_order/db/migrate/20260407111859_add_proposed_time_to_orders.rb
new file mode 100644
index 0000000..4b040ee
--- /dev/null
+++ b/affordance_order/db/migrate/20260407111859_add_proposed_time_to_orders.rb
@@ -0,0 +1,6 @@
+class AddProposedTimeToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :proposed_time, :datetime
+    add_column :orders, :proposal_reason, :text
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..0f954e2 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_111859) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -41,11 +41,18 @@
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
+    t.text "proposal_reason"
+    t.datetime "proposed_at"
+    t.integer "proposed_duration_minutes"
+    t.datetime "proposed_scheduled_at"
+    t.datetime "proposed_time"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
```
