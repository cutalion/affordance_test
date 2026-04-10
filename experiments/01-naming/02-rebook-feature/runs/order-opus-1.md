# Experiment: 02-rebook-feature
# App: order | Model: opus | Run: 1
# Branch: experiment/02-rebook-feature/order/opus/run-1

---

## Claude Output

The rebook feature is implemented and committed. Here's a summary of what was added:

### Changes

**`app/models/order.rb`**
- Added `rebookable?` instance method — returns `true` for completed, canceled, or rejected orders
- Added `rebookable` scope for querying rebookable orders

**`app/services/orders/rebook_service.rb`** (new)
- Takes an existing order, the client, and params (notably `scheduled_at`)
- Validates the order is in a rebookable state and belongs to the client
- Delegates to `Orders::CreateService`, reusing **provider**, **location**, **duration**, **amount**, and **currency** from the original order
- Allows the client to override `duration_minutes`, `location`, and `notes`

**`app/controllers/api/orders_controller.rb`**
- Added `rebook` action (client-only, returns 403 for providers)
- Added `rebook_params` helper (permits `scheduled_at`, `duration_minutes`, `location`, `notes`)

**`config/routes.rb`**
- Added `post :rebook` as a member route on orders → `POST /api/orders/:id/rebook`

**`spec/services/orders/rebook_service_spec.rb`** (new) — 7 examples covering:
- Reusing provider/location/duration/pricing from original
- Overriding duration and location
- Rejecting non-rebookable states, other clients' orders, and missing `scheduled_at`

**`spec/requests/api/orders_spec.rb`** — 5 new request specs covering the endpoint end-to-end

All **277 tests** pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..d9c975e 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       orders = scoped_orders
@@ -90,6 +90,25 @@ def reject
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      result = Orders::RebookService.new(
+        order: @order,
+        client: client,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: order_detail_json(result[:order]), status: :created
+      elsif result[:errors]
+        render_unprocessable(result[:errors].full_messages)
+      else
+        render json: { error: result[:error] }, status: :unprocessable_entity
+      end
+    end
+
     private
 
     def set_order
@@ -109,6 +128,10 @@ def order_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..b4d1652 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -26,6 +26,11 @@ class Order < ApplicationRecord
     scope
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
+  scope :rebookable, -> { where(state: [:completed, :canceled, :rejected]) }
+
+  def rebookable?
+    completed? || canceled? || rejected?
+  end
 
   aasm column: :state do
     state :pending, initial: true
diff --git a/affordance_order/app/services/orders/rebook_service.rb b/affordance_order/app/services/orders/rebook_service.rb
new file mode 100644
index 0000000..5c88a9e
--- /dev/null
+++ b/affordance_order/app/services/orders/rebook_service.rb
@@ -0,0 +1,44 @@
+module Orders
+  class RebookService
+    def initialize(order:, client:, params:)
+      @order = order
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @order.rebookable?
+        return { success: false, error: "Order cannot be rebooked in its current state" }
+      end
+
+      unless @order.client_id == @client.id
+        return { success: false, error: "You can only rebook your own orders" }
+      end
+
+      result = Orders::CreateService.new(
+        client: @client,
+        provider: @order.provider,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        { success: true, order: result[:order] }
+      else
+        { success: false, errors: result[:errors] }
+      end
+    end
+
+    private
+
+    def rebook_params
+      {
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes] || @order.duration_minutes,
+        location: @params[:location] || @order.location,
+        notes: @params[:notes],
+        amount_cents: @order.amount_cents,
+        currency: @order.currency
+      }
+    end
+  end
+end
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..12bf77e 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -17,6 +17,7 @@
         patch :complete
         patch :cancel
         patch :reject
+        post :rebook
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..2bb4ce5 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -166,6 +166,60 @@
     end
   end
 
+  describe "POST /api/orders/:id/rebook" do
+    let(:original_order) { create(:order, :completed, client: client, provider: provider, location: "123 Main St", duration_minutes: 90) }
+
+    it "creates a new order based on a previous one" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(90)
+    end
+
+    it "allows overriding duration and location" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601, duration_minutes: 60, location: "New Place" },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["duration_minutes"]).to eq(60)
+      expect(body["location"]).to eq("New Place")
+    end
+
+    it "returns 403 for provider" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when rebooking a pending order" do
+      pending_order = create(:order, client: client, provider: provider)
+      post "/api/orders/#{pending_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns error when another client tries to rebook" do
+      other_client = create(:client)
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/orders/:id/reject" do
     let(:order) { create(:order, :confirmed, client: client, provider: provider) }
 
diff --git a/affordance_order/spec/services/orders/rebook_service_spec.rb b/affordance_order/spec/services/orders/rebook_service_spec.rb
new file mode 100644
index 0000000..30e4fe0
--- /dev/null
+++ b/affordance_order/spec/services/orders/rebook_service_spec.rb
@@ -0,0 +1,69 @@
+require "rails_helper"
+
+RSpec.describe Orders::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_order) { create(:order, :completed, client: client, provider: provider, location: "123 Main St", duration_minutes: 90) }
+
+  describe "#call" do
+    let(:params) { { scheduled_at: 5.days.from_now.iso8601 } }
+
+    it "creates a new order reusing provider, location, and duration from original" do
+      result = described_class.new(order: original_order, client: client, params: params).call
+
+      expect(result[:success]).to be true
+      new_order = result[:order]
+      expect(new_order.provider_id).to eq(original_order.provider_id)
+      expect(new_order.location).to eq(original_order.location)
+      expect(new_order.duration_minutes).to eq(original_order.duration_minutes)
+      expect(new_order.amount_cents).to eq(original_order.amount_cents)
+      expect(new_order.currency).to eq(original_order.currency)
+      expect(new_order.state).to eq("pending")
+    end
+
+    it "allows overriding duration and location" do
+      override_params = params.merge(duration_minutes: 60, location: "456 Oak Ave")
+      result = described_class.new(order: original_order, client: client, params: override_params).call
+
+      expect(result[:success]).to be true
+      expect(result[:order].duration_minutes).to eq(60)
+      expect(result[:order].location).to eq("456 Oak Ave")
+    end
+
+    it "fails when order is in pending state" do
+      pending_order = create(:order, client: client, provider: provider)
+      result = described_class.new(order: pending_order, client: client, params: params).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("cannot be rebooked")
+    end
+
+    it "allows rebooking canceled orders" do
+      canceled_order = create(:order, :canceled, client: client, provider: provider)
+      result = described_class.new(order: canceled_order, client: client, params: params).call
+
+      expect(result[:success]).to be true
+    end
+
+    it "allows rebooking rejected orders" do
+      rejected_order = create(:order, :rejected, client: client, provider: provider)
+      result = described_class.new(order: rejected_order, client: client, params: params).call
+
+      expect(result[:success]).to be true
+    end
+
+    it "fails when client does not own the order" do
+      other_client = create(:client)
+      result = described_class.new(order: original_order, client: other_client, params: params).call
+
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("your own orders")
+    end
+
+    it "fails when scheduled_at is missing" do
+      result = described_class.new(order: original_order, client: client, params: {}).call
+
+      expect(result[:success]).to be false
+    end
+  end
+end
```
