# Experiment: 02-rebook-feature
# App: order | Model: opus | Run: 2
# Branch: experiment/02-rebook-feature/order/opus/run-2

---

## Claude Output

The rebook feature is implemented and committed. Here's a summary of what was added:

### New files
- **`app/services/orders/rebook_service.rb`** — Service that creates a new order from a previous one, reusing provider, location, duration, amount, and currency. Only completed or canceled orders can be rebooked, and only by the owning client.
- **`spec/services/orders/rebook_service_spec.rb`** — 6 test cases covering happy path (completed/canceled), ownership validation, state validation, optional overrides, and missing params.

### Modified files
- **`config/routes.rb`** — Added `post :rebook` member route on orders.
- **`app/controllers/api/orders_controller.rb`** — Added `rebook` action and `rebook_params` method. The action requires client auth, delegates to `RebookService`, and returns the new order (201) or errors (422).
- **`spec/requests/api/orders_spec.rb`** — 6 request specs covering: rebooking completed/canceled orders, rejecting pending orders, provider auth (403), wrong client (422), and location override.

All 36 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..d456371 100644
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
+        original_order: @order,
+        client: client,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: order_detail_json(result[:order]), status: :created
+      elsif result[:error]
+        render json: { error: result[:error] }, status: :unprocessable_entity
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     private
 
     def set_order
@@ -109,6 +128,10 @@ def order_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :location, :notes)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/services/orders/rebook_service.rb b/affordance_order/app/services/orders/rebook_service.rb
new file mode 100644
index 0000000..2a1cccc
--- /dev/null
+++ b/affordance_order/app/services/orders/rebook_service.rb
@@ -0,0 +1,38 @@
+module Orders
+  class RebookService
+    def initialize(original_order:, client:, params:)
+      @original_order = original_order
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @original_order.client_id == @client.id
+        return { success: false, error: "Order does not belong to this client" }
+      end
+
+      unless @original_order.completed? || @original_order.canceled?
+        return { success: false, error: "Can only rebook completed or canceled orders" }
+      end
+
+      Orders::CreateService.new(
+        client: @client,
+        provider: @original_order.provider,
+        params: rebook_params
+      ).call
+    end
+
+    private
+
+    def rebook_params
+      {
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @original_order.duration_minutes,
+        location: @params[:location] || @original_order.location,
+        notes: @params[:notes],
+        amount_cents: @original_order.amount_cents,
+        currency: @original_order.currency
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
index b5e1bbb..cae9276 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -180,4 +180,55 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/orders/:id/rebook" do
+    let(:completed_order) do
+      create(:order, :completed, client: client, provider: provider,
+        location: "123 Main St", duration_minutes: 90, amount_cents: 500_000)
+    end
+    let(:rebook_params) { { scheduled_at: 5.days.from_now.iso8601 } }
+
+    it "creates a new order based on a completed order" do
+      post "/api/orders/#{completed_order.id}/rebook", params: rebook_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(90)
+      expect(body["amount_cents"]).to eq(500_000)
+    end
+
+    it "creates a new order based on a canceled order" do
+      canceled_order = create(:order, :canceled, client: client, provider: provider)
+      post "/api/orders/#{canceled_order.id}/rebook", params: rebook_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+    end
+
+    it "returns error when rebooking a pending order" do
+      pending_order = create(:order, client: client, provider: provider)
+      post "/api/orders/#{pending_order.id}/rebook", params: rebook_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/orders/#{completed_order.id}/rebook", params: rebook_params, headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when another client tries to rebook" do
+      other_client = create(:client)
+      post "/api/orders/#{completed_order.id}/rebook", params: rebook_params, headers: auth_headers(other_client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "allows overriding location" do
+      post "/api/orders/#{completed_order.id}/rebook",
+        params: rebook_params.merge(location: "New Location"),
+        headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["location"]).to eq("New Location")
+    end
+  end
 end
diff --git a/affordance_order/spec/services/orders/rebook_service_spec.rb b/affordance_order/spec/services/orders/rebook_service_spec.rb
new file mode 100644
index 0000000..b4fa023
--- /dev/null
+++ b/affordance_order/spec/services/orders/rebook_service_spec.rb
@@ -0,0 +1,99 @@
+require "rails_helper"
+
+RSpec.describe Orders::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_order) do
+    create(:order, :completed,
+      client: client,
+      provider: provider,
+      location: "123 Main St",
+      duration_minutes: 90,
+      amount_cents: 500_000,
+      currency: "RUB"
+    )
+  end
+  let(:params) { { scheduled_at: 5.days.from_now } }
+
+  subject(:result) do
+    described_class.new(original_order: original_order, client: client, params: params).call
+  end
+
+  describe "#call" do
+    context "with a completed order" do
+      it "creates a new order reusing provider, location, and duration" do
+        expect(result[:success]).to be true
+        new_order = result[:order]
+        expect(new_order.provider_id).to eq(provider.id)
+        expect(new_order.client_id).to eq(client.id)
+        expect(new_order.location).to eq("123 Main St")
+        expect(new_order.duration_minutes).to eq(90)
+        expect(new_order.amount_cents).to eq(500_000)
+        expect(new_order.currency).to eq("RUB")
+        expect(new_order.state).to eq("pending")
+      end
+
+      it "uses the new scheduled_at" do
+        new_order = result[:order]
+        expect(new_order.scheduled_at).to be_within(1.second).of(5.days.from_now)
+      end
+
+      it "creates a payment for the new order" do
+        expect { result }.to change(Payment, :count).by(1)
+      end
+    end
+
+    context "with a canceled order" do
+      let(:original_order) do
+        create(:order, :canceled, client: client, provider: provider,
+          location: "456 Oak Ave", duration_minutes: 60, amount_cents: 200_000)
+      end
+
+      it "allows rebooking" do
+        expect(result[:success]).to be true
+        expect(result[:order].location).to eq("456 Oak Ave")
+      end
+    end
+
+    context "with a pending order" do
+      let(:original_order) { create(:order, client: client, provider: provider) }
+
+      it "rejects rebooking" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Can only rebook completed or canceled orders")
+      end
+    end
+
+    context "when client does not own the order" do
+      let(:other_client) { create(:client) }
+
+      subject(:result) do
+        described_class.new(original_order: original_order, client: other_client, params: params).call
+      end
+
+      it "rejects rebooking" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Order does not belong to this client")
+      end
+    end
+
+    context "with optional overrides" do
+      let(:params) { { scheduled_at: 5.days.from_now, location: "789 New Place", notes: "New notes" } }
+
+      it "allows overriding location and notes" do
+        new_order = result[:order]
+        expect(new_order.location).to eq("789 New Place")
+        expect(new_order.notes).to eq("New notes")
+      end
+    end
+
+    context "with missing scheduled_at" do
+      let(:params) { {} }
+
+      it "returns validation errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+    end
+  end
+end
```
