# Experiment: 02-rebook-feature
# App: order | Model: opus | Run: 3
# Branch: experiment/02-rebook-feature/order/opus/run-3

---

## Claude Output

The rebook feature has been implemented and committed. Here's a summary of what was added:

### Changes

1. **`app/models/order.rb`** — Added `rebookable?` (returns true for completed/canceled/rejected orders) and `rebook_attributes` (extracts provider_id, location, duration_minutes, amount_cents, currency).

2. **`app/services/orders/rebook_service.rb`** — New service that validates ownership and rebookable state, then delegates to `Orders::CreateService` with the original order's attributes plus a new `scheduled_at` and optional `notes`.

3. **`app/controllers/api/orders_controller.rb`** — Added `rebook` action (client-only, returns 201 on success) with `rebook_params` permitting `scheduled_at` and `notes`.

4. **`config/routes.rb`** — Added `post :rebook` as a member route on orders.

5. **Specs** — Full test coverage:
   - Model specs for `rebookable?` (all 6 states) and `rebook_attributes`
   - Service spec covering completed/canceled/rejected orders, notes override, wrong state, and wrong client
   - Request spec covering happy paths, forbidden for providers, not found, and unprocessable states

All **70 tests pass**.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..dc5d26e 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       orders = scoped_orders
@@ -90,6 +90,24 @@ def reject
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
+      else
+        error_msg = result[:errors] ? result[:errors].full_messages : [result[:error]]
+        render_unprocessable(error_msg)
+      end
+    end
+
     private
 
     def set_order
@@ -109,6 +127,10 @@ def order_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :notes)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/models/order.rb b/affordance_order/app/models/order.rb
index 63b3254..10c7866 100644
--- a/affordance_order/app/models/order.rb
+++ b/affordance_order/app/models/order.rb
@@ -27,6 +27,20 @@ class Order < ApplicationRecord
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
 
+  def rebookable?
+    completed? || canceled? || rejected?
+  end
+
+  def rebook_attributes
+    {
+      provider_id: provider_id,
+      location: location,
+      duration_minutes: duration_minutes,
+      amount_cents: amount_cents,
+      currency: currency
+    }
+  end
+
   aasm column: :state do
     state :pending, initial: true
     state :confirmed
diff --git a/affordance_order/app/services/orders/rebook_service.rb b/affordance_order/app/services/orders/rebook_service.rb
new file mode 100644
index 0000000..0f82c5c
--- /dev/null
+++ b/affordance_order/app/services/orders/rebook_service.rb
@@ -0,0 +1,30 @@
+module Orders
+  class RebookService
+    def initialize(order:, client:, params:)
+      @order = order
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @order.client_id == @client.id
+        return { success: false, error: "Order does not belong to this client" }
+      end
+
+      unless @order.rebookable?
+        return { success: false, error: "Order cannot be rebooked in its current state" }
+      end
+
+      create_params = @order.rebook_attributes.merge(
+        scheduled_at: @params[:scheduled_at],
+        notes: @params[:notes]
+      )
+
+      Orders::CreateService.new(
+        client: @client,
+        provider: @order.provider,
+        params: create_params
+      ).call
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
diff --git a/affordance_order/spec/models/order_spec.rb b/affordance_order/spec/models/order_spec.rb
index 6686df0..5552c5a 100644
--- a/affordance_order/spec/models/order_spec.rb
+++ b/affordance_order/spec/models/order_spec.rb
@@ -142,6 +142,45 @@
     end
   end
 
+  describe "#rebookable?" do
+    it "returns true for completed orders" do
+      expect(build(:order, :completed)).to be_rebookable
+    end
+
+    it "returns true for canceled orders" do
+      expect(build(:order, :canceled)).to be_rebookable
+    end
+
+    it "returns true for rejected orders" do
+      expect(build(:order, :rejected)).to be_rebookable
+    end
+
+    it "returns false for pending orders" do
+      expect(build(:order)).not_to be_rebookable
+    end
+
+    it "returns false for confirmed orders" do
+      expect(build(:order, :confirmed)).not_to be_rebookable
+    end
+
+    it "returns false for in_progress orders" do
+      expect(build(:order, :in_progress)).not_to be_rebookable
+    end
+  end
+
+  describe "#rebook_attributes" do
+    it "returns provider_id, location, duration_minutes, amount_cents, and currency" do
+      order = build(:order, location: "Test Location", duration_minutes: 60, amount_cents: 500_00, currency: "RUB")
+      attrs = order.rebook_attributes
+
+      expect(attrs[:provider_id]).to eq(order.provider_id)
+      expect(attrs[:location]).to eq("Test Location")
+      expect(attrs[:duration_minutes]).to eq(60)
+      expect(attrs[:amount_cents]).to eq(500_00)
+      expect(attrs[:currency]).to eq("RUB")
+    end
+  end
+
   describe "scopes" do
     let!(:future_order) { create(:order, scheduled_at: 1.day.from_now) }
     let!(:past_order) { create(:order, scheduled_at: 1.day.ago) }
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..d2981e7 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -166,6 +166,67 @@
     end
   end
 
+  describe "POST /api/orders/:id/rebook" do
+    context "with a completed order" do
+      let(:order) { create(:order, :completed, client: client, provider: provider, location: "456 Oak Ave", duration_minutes: 90) }
+
+      it "creates a new order reusing provider, location, and duration" do
+        post "/api/orders/#{order.id}/rebook",
+          params: { scheduled_at: 5.days.from_now.iso8601 },
+          headers: auth_headers(client)
+
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(provider.id)
+        expect(body["location"]).to eq("456 Oak Ave")
+        expect(body["duration_minutes"]).to eq(90)
+        expect(body["state"]).to eq("pending")
+        expect(body["id"]).not_to eq(order.id)
+      end
+    end
+
+    context "with a canceled order" do
+      let(:order) { create(:order, :canceled, client: client, provider: provider) }
+
+      it "allows rebooking" do
+        post "/api/orders/#{order.id}/rebook",
+          params: { scheduled_at: 5.days.from_now.iso8601 },
+          headers: auth_headers(client)
+
+        expect(response).to have_http_status(:created)
+      end
+    end
+
+    context "with a pending order" do
+      let(:order) { create(:order, client: client, provider: provider) }
+
+      it "returns an error" do
+        post "/api/orders/#{order.id}/rebook",
+          params: { scheduled_at: 5.days.from_now.iso8601 },
+          headers: auth_headers(client)
+
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
+
+    it "returns 403 for provider" do
+      order = create(:order, :completed, client: client, provider: provider)
+      post "/api/orders/#{order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for unknown order" do
+      post "/api/orders/99999/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:not_found)
+    end
+  end
+
   describe "PATCH /api/orders/:id/reject" do
     let(:order) { create(:order, :confirmed, client: client, provider: provider) }
 
diff --git a/affordance_order/spec/services/orders/rebook_service_spec.rb b/affordance_order/spec/services/orders/rebook_service_spec.rb
new file mode 100644
index 0000000..75b630a
--- /dev/null
+++ b/affordance_order/spec/services/orders/rebook_service_spec.rb
@@ -0,0 +1,101 @@
+require "rails_helper"
+
+RSpec.describe Orders::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+
+  describe "#call" do
+    context "when the order is completed" do
+      let(:order) { create(:order, :completed, client: client, provider: provider, location: "123 Main St", duration_minutes: 90) }
+
+      it "creates a new order reusing provider, location, and duration" do
+        result = described_class.new(
+          order: order,
+          client: client,
+          params: { scheduled_at: 5.days.from_now.iso8601 }
+        ).call
+
+        expect(result[:success]).to be true
+        new_order = result[:order]
+        expect(new_order.id).not_to eq(order.id)
+        expect(new_order.provider_id).to eq(provider.id)
+        expect(new_order.client_id).to eq(client.id)
+        expect(new_order.location).to eq("123 Main St")
+        expect(new_order.duration_minutes).to eq(90)
+        expect(new_order.amount_cents).to eq(order.amount_cents)
+        expect(new_order.currency).to eq(order.currency)
+        expect(new_order.state).to eq("pending")
+      end
+
+      it "allows overriding notes" do
+        result = described_class.new(
+          order: order,
+          client: client,
+          params: { scheduled_at: 5.days.from_now.iso8601, notes: "New notes" }
+        ).call
+
+        expect(result[:success]).to be true
+        expect(result[:order].notes).to eq("New notes")
+      end
+    end
+
+    context "when the order is canceled" do
+      let(:order) { create(:order, :canceled, client: client, provider: provider) }
+
+      it "allows rebooking" do
+        result = described_class.new(
+          order: order,
+          client: client,
+          params: { scheduled_at: 5.days.from_now.iso8601 }
+        ).call
+
+        expect(result[:success]).to be true
+      end
+    end
+
+    context "when the order is rejected" do
+      let(:order) { create(:order, :rejected, client: client, provider: provider) }
+
+      it "allows rebooking" do
+        result = described_class.new(
+          order: order,
+          client: client,
+          params: { scheduled_at: 5.days.from_now.iso8601 }
+        ).call
+
+        expect(result[:success]).to be true
+      end
+    end
+
+    context "when the order is pending" do
+      let(:order) { create(:order, client: client, provider: provider) }
+
+      it "returns an error" do
+        result = described_class.new(
+          order: order,
+          client: client,
+          params: { scheduled_at: 5.days.from_now.iso8601 }
+        ).call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("cannot be rebooked")
+      end
+    end
+
+    context "when the order belongs to a different client" do
+      let(:other_client) { create(:client) }
+      let(:order) { create(:order, :completed, client: other_client, provider: provider) }
+
+      it "returns an error" do
+        result = described_class.new(
+          order: order,
+          client: client,
+          params: { scheduled_at: 5.days.from_now.iso8601 }
+        ).call
+
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("does not belong")
+      end
+    end
+  end
+end
```
