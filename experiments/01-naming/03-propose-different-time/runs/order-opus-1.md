# Experiment: 03-propose-different-time
# App: order | Model: opus | Run: 1
# Branch: experiment/03-propose-different-time/order/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**New state: `provider_proposed_time`** — added to the order state machine between `pending` and `confirmed`.

**Flow:**
1. **Provider proposes a new time** (`PATCH /api/orders/:id/propose_new_time`) — transitions from `pending` → `provider_proposed_time`, stores `proposed_scheduled_at`
2. **Client accepts** (`PATCH /api/orders/:id/accept_proposed_time`) — transitions to `confirmed`, updates `scheduled_at` to the proposed time
3. **Client declines** (`PATCH /api/orders/:id/decline_proposed_time`) — returns to `pending`, clears the proposal

**Files changed:**
- `app/models/order.rb` — new state + 3 events + validation
- `app/controllers/api/orders_controller.rb` — 3 new actions
- `config/routes.rb` — 3 new routes
- `db/migrate/` — adds `proposed_scheduled_at` column
- 3 new service classes in `app/services/orders/`
- 3 new mailer methods + views for notifications
- Specs: 28 new tests, all 293 passing

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..77b67c0 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :propose_new_time, :accept_proposed_time, :decline_proposed_time, :start, :complete, :cancel, :reject]
 
     def index
       orders = scoped_orders
@@ -42,6 +42,38 @@ def confirm
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
+    def accept_proposed_time
+      client = current_client!
+      return if performed?
+
+      result = Orders::AcceptProposedTimeService.new(order: @order, client: client).call
+      handle_service_result(result)
+    end
+
+    def decline_proposed_time
+      client = current_client!
+      return if performed?
+
+      result = Orders::DeclineProposedTimeService.new(order: @order, client: client).call
+      handle_service_result(result)
+    end
+
     def start
       provider = current_provider!
       return if performed?
@@ -139,6 +171,7 @@ def order_detail_json(order)
         notes: order.notes,
         amount_cents: order.amount_cents,
         currency: order.currency,
+        proposed_scheduled_at: order.proposed_scheduled_at,
         cancel_reason: order.cancel_reason,
         reject_reason: order.reject_reason,
         started_at: order.started_at,
diff --git a/affordance_order/app/mailers/order_mailer.rb b/affordance_order/app/mailers/order_mailer.rb
index 428fd89..e0b93dd 100644
--- a/affordance_order/app/mailers/order_mailer.rb
+++ b/affordance_order/app/mailers/order_mailer.rb
@@ -29,6 +29,25 @@ def order_canceled(recipient, payload)
     mail(to: recipient.email, subject: "Order ##{@order_id} canceled")
   end
 
+  def order_time_proposed(recipient, payload)
+    @recipient = recipient
+    @order_id = payload[:order_id]
+    @proposed_scheduled_at = payload[:proposed_scheduled_at]
+    mail(to: recipient.email, subject: "New time proposed for order ##{@order_id}")
+  end
+
+  def order_proposed_time_accepted(recipient, payload)
+    @recipient = recipient
+    @order_id = payload[:order_id]
+    mail(to: recipient.email, subject: "Proposed time accepted for order ##{@order_id}")
+  end
+
+  def order_proposed_time_declined(recipient, payload)
+    @recipient = recipient
+    @order_id = payload[:order_id]
+    mail(to: recipient.email, subject: "Proposed time declined for order ##{@order_id}")
+  end
+
   def order_rejected(recipient, payload)
     @recipient = recipient
     @order_id = payload[:order_id]
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..9dd6093 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -13,6 +13,7 @@ class Order < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { provider_proposed_time? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -34,11 +35,30 @@ class Order < ApplicationRecord
     state :completed
     state :canceled
     state :rejected
+    state :provider_proposed_time
 
     event :confirm do
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_new_time do
+      transitions from: :pending, to: :provider_proposed_time
+    end
+
+    event :accept_proposed_time do
+      transitions from: :provider_proposed_time, to: :confirmed
+      after do
+        update!(scheduled_at: proposed_scheduled_at, proposed_scheduled_at: nil)
+      end
+    end
+
+    event :decline_proposed_time do
+      transitions from: :provider_proposed_time, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil)
+      end
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
@@ -54,7 +74,7 @@ class Order < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :confirmed], to: :canceled
+      transitions from: [:pending, :confirmed, :provider_proposed_time], to: :canceled
     end
 
     event :reject do
diff --git a/affordance_order/app/services/orders/accept_proposed_time_service.rb b/affordance_order/app/services/orders/accept_proposed_time_service.rb
new file mode 100644
index 0000000..168bc43
--- /dev/null
+++ b/affordance_order/app/services/orders/accept_proposed_time_service.rb
@@ -0,0 +1,24 @@
+module Orders
+  class AcceptProposedTimeService
+    def initialize(order:, client:)
+      @order = order
+      @client = client
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+
+      @order.accept_proposed_time!
+      NotificationService.notify(@order.provider, :order_proposed_time_accepted, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot accept proposed time for order in #{@order.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_order/app/services/orders/decline_proposed_time_service.rb b/affordance_order/app/services/orders/decline_proposed_time_service.rb
new file mode 100644
index 0000000..e7b7135
--- /dev/null
+++ b/affordance_order/app/services/orders/decline_proposed_time_service.rb
@@ -0,0 +1,24 @@
+module Orders
+  class DeclineProposedTimeService
+    def initialize(order:, client:)
+      @order = order
+      @client = client
+    end
+
+    def call
+      return error("Not your order") unless @order.client_id == @client.id
+
+      @order.decline_proposed_time!
+      NotificationService.notify(@order.provider, :order_proposed_time_declined, order_id: @order.id)
+      { success: true, order: @order }
+    rescue AASM::InvalidTransition
+      error("Cannot decline proposed time for order in #{@order.state} state")
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
index 0000000..1b6bb0d
--- /dev/null
+++ b/affordance_order/app/services/orders/propose_new_time_service.rb
@@ -0,0 +1,30 @@
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
+      parsed_time = Time.zone.parse(@proposed_scheduled_at.to_s) rescue nil
+      return error("Invalid proposed time") unless parsed_time
+
+      @order.proposed_scheduled_at = parsed_time
+      @order.propose_new_time!
+      NotificationService.notify(@order.client, :order_time_proposed, order_id: @order.id, proposed_scheduled_at: parsed_time.iso8601)
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
diff --git a/affordance_order/app/views/order_mailer/order_proposed_time_accepted.text.erb b/affordance_order/app/views/order_mailer/order_proposed_time_accepted.text.erb
new file mode 100644
index 0000000..4857c36
--- /dev/null
+++ b/affordance_order/app/views/order_mailer/order_proposed_time_accepted.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, your proposed time for order #<%= @order_id %> has been accepted.
diff --git a/affordance_order/app/views/order_mailer/order_proposed_time_declined.text.erb b/affordance_order/app/views/order_mailer/order_proposed_time_declined.text.erb
new file mode 100644
index 0000000..901d0d0
--- /dev/null
+++ b/affordance_order/app/views/order_mailer/order_proposed_time_declined.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, your proposed time for order #<%= @order_id %> has been declined.
diff --git a/affordance_order/app/views/order_mailer/order_time_proposed.text.erb b/affordance_order/app/views/order_mailer/order_time_proposed.text.erb
new file mode 100644
index 0000000..08aa53a
--- /dev/null
+++ b/affordance_order/app/views/order_mailer/order_time_proposed.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, a new time has been proposed for order #<%= @order_id %>: <%= @proposed_scheduled_at %>.
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..cf8aabb 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -13,6 +13,9 @@
     resources :orders, only: [:index, :show, :create] do
       member do
         patch :confirm
+        patch :propose_new_time
+        patch :accept_proposed_time
+        patch :decline_proposed_time
         patch :start
         patch :complete
         patch :cancel
diff --git a/affordance_order/db/migrate/20260407103756_add_proposed_scheduled_at_to_orders.rb b/affordance_order/db/migrate/20260407103756_add_proposed_scheduled_at_to_orders.rb
new file mode 100644
index 0000000..e764149
--- /dev/null
+++ b/affordance_order/db/migrate/20260407103756_add_proposed_scheduled_at_to_orders.rb
@@ -0,0 +1,5 @@
+class AddProposedScheduledAtToOrders < ActiveRecord::Migration[8.1]
+  def change
+    add_column :orders, :proposed_scheduled_at, :datetime
+  end
+end
diff --git a/affordance_order/db/schema.rb b/affordance_order/db/schema.rb
index 75eeb83..98ebe19 100644
--- a/affordance_order/db/schema.rb
+++ b/affordance_order/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_103756) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -46,6 +46,7 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_order/spec/factories/orders.rb b/affordance_order/spec/factories/orders.rb
index 81b3def..7ce24bf 100644
--- a/affordance_order/spec/factories/orders.rb
+++ b/affordance_order/spec/factories/orders.rb
@@ -34,6 +34,11 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :provider_proposed_time do
+      state { "provider_proposed_time" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :with_payment do
       after(:create) do |order|
         create(:payment, order: order, amount_cents: order.amount_cents, currency: order.currency)
diff --git a/affordance_order/spec/models/order_spec.rb b/affordance_order/spec/models/order_spec.rb
index 6686df0..f65d6b8 100644
--- a/affordance_order/spec/models/order_spec.rb
+++ b/affordance_order/spec/models/order_spec.rb
@@ -45,6 +45,14 @@
         expect(order.errors[:reject_reason]).to be_present
       end
     end
+
+    context "when provider_proposed_time" do
+      it "requires proposed_scheduled_at" do
+        order = build(:order, :provider_proposed_time, proposed_scheduled_at: nil)
+        expect(order).not_to be_valid
+        expect(order.errors[:proposed_scheduled_at]).to be_present
+      end
+    end
   end
 
   describe "state machine" do
@@ -99,6 +107,57 @@
       end
     end
 
+    describe "propose_new_time event" do
+      it "transitions from pending to provider_proposed_time" do
+        order.update!(proposed_scheduled_at: 5.days.from_now)
+        order.propose_new_time!
+        expect(order).to be_provider_proposed_time
+      end
+
+      it "cannot propose from confirmed" do
+        order.confirm!
+        expect { order.propose_new_time! }.to raise_error(AASM::InvalidTransition)
+      end
+    end
+
+    describe "accept_proposed_time event" do
+      let(:proposed_time) { 5.days.from_now }
+
+      before do
+        order.update!(proposed_scheduled_at: proposed_time)
+        order.propose_new_time!
+      end
+
+      it "transitions from provider_proposed_time to confirmed" do
+        order.accept_proposed_time!
+        expect(order).to be_confirmed
+      end
+
+      it "updates scheduled_at and clears proposed_scheduled_at" do
+        order.accept_proposed_time!
+        order.reload
+        expect(order.scheduled_at).to be_within(1.second).of(proposed_time)
+        expect(order.proposed_scheduled_at).to be_nil
+      end
+    end
+
+    describe "decline_proposed_time event" do
+      before do
+        order.update!(proposed_scheduled_at: 5.days.from_now)
+        order.propose_new_time!
+      end
+
+      it "transitions from provider_proposed_time to pending" do
+        order.decline_proposed_time!
+        expect(order).to be_pending
+      end
+
+      it "clears proposed_scheduled_at" do
+        order.decline_proposed_time!
+        expect(order.reload.proposed_scheduled_at).to be_nil
+      end
+    end
+
     describe "cancel event" do
       it "transitions from pending to canceled" do
         order.update!(cancel_reason: "Changed my mind")
@@ -113,6 +172,14 @@
         expect(order).to be_canceled
       end
 
+      it "transitions from provider_proposed_time to canceled" do
+        order.update!(proposed_scheduled_at: 5.days.from_now)
+        order.propose_new_time!
+        order.update!(cancel_reason: "Changed my mind")
+        order.cancel!
+        expect(order).to be_canceled
+      end
+
       it "cannot cancel from in_progress" do
         order.confirm!
         order.start!
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..72cac2a 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -166,6 +166,63 @@
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
+      expect(body["state"]).to eq("provider_proposed_time")
+      expect(body["proposed_scheduled_at"]).to be_present
+    end
+
+    it "returns 403 for client" do
+      patch "/api/orders/#{order.id}/propose_new_time", params: { proposed_scheduled_at: proposed_time }, headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/orders/#{order.id}/propose_new_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/accept_proposed_time" do
+    let(:order) { create(:order, :provider_proposed_time, client: client, provider: provider) }
+
+    it "accepts the proposed time as client" do
+      patch "/api/orders/#{order.id}/accept_proposed_time", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+      expect(body["proposed_scheduled_at"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/accept_proposed_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/orders/:id/decline_proposed_time" do
+    let(:order) { create(:order, :provider_proposed_time, client: client, provider: provider) }
+
+    it "declines the proposed time as client" do
+      patch "/api/orders/#{order.id}/decline_proposed_time", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["proposed_scheduled_at"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/orders/#{order.id}/decline_proposed_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
   describe "PATCH /api/orders/:id/reject" do
     let(:order) { create(:order, :confirmed, client: client, provider: provider) }
 
diff --git a/affordance_order/spec/services/orders/accept_proposed_time_service_spec.rb b/affordance_order/spec/services/orders/accept_proposed_time_service_spec.rb
new file mode 100644
index 0000000..6efc861
--- /dev/null
+++ b/affordance_order/spec/services/orders/accept_proposed_time_service_spec.rb
@@ -0,0 +1,38 @@
+require "rails_helper"
+
+RSpec.describe Orders::AcceptProposedTimeService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:order) { create(:order, :provider_proposed_time, client: client, provider: provider, proposed_scheduled_at: proposed_time) }
+
+  describe "#call" do
+    it "accepts the proposed time and updates scheduled_at" do
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
+      expect(read_notification_log).to include("event=order_proposed_time_accepted")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(order: order, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails for non-proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept proposed time")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/decline_proposed_time_service_spec.rb b/affordance_order/spec/services/orders/decline_proposed_time_service_spec.rb
new file mode 100644
index 0000000..9dcf9fb
--- /dev/null
+++ b/affordance_order/spec/services/orders/decline_proposed_time_service_spec.rb
@@ -0,0 +1,36 @@
+require "rails_helper"
+
+RSpec.describe Orders::DeclineProposedTimeService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:order) { create(:order, :provider_proposed_time, client: client, provider: provider) }
+
+  describe "#call" do
+    it "declines the proposed time and returns to pending" do
+      result = described_class.new(order: order, client: client).call
+      expect(result[:success]).to be true
+      order.reload
+      expect(order.state).to eq("pending")
+      expect(order.proposed_scheduled_at).to be_nil
+    end
+
+    it "notifies the provider" do
+      described_class.new(order: order, client: client).call
+      expect(read_notification_log).to include("event=order_proposed_time_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(order: order, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your order")
+    end
+
+    it "fails for non-proposed order" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline proposed time")
+    end
+  end
+end
diff --git a/affordance_order/spec/services/orders/propose_new_time_service_spec.rb b/affordance_order/spec/services/orders/propose_new_time_service_spec.rb
new file mode 100644
index 0000000..74404f5
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
+  let(:proposed_time) { 5.days.from_now.iso8601 }
+
+  describe "#call" do
+    it "proposes a new time for a pending order" do
+      result = described_class.new(order: order, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be true
+      expect(order.reload.state).to eq("provider_proposed_time")
+      expect(order.proposed_scheduled_at).to be_present
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
