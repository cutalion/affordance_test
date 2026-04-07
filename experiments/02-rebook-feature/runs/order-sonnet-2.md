# Experiment: 02-rebook-feature
# App: order | Model: sonnet | Run: 2
# Branch: experiment/02-rebook-feature/order/sonnet/run-2

---

## Claude Output

The rebook feature is implemented and committed. Here's a summary of what was added:

### Changes

**`app/services/orders/rebook_service.rb`** *(new)*
- Accepts an `original_order`, the requesting `client`, and new `params`
- Validates that the client owns the original order (returns a `Forbidden` error otherwise)
- Creates a new `Order` reusing `provider`, `location`, `duration_minutes`, `amount_cents`, and `currency` from the original
- Accepts a new `scheduled_at` (required) and optional `notes`
- Creates the associated `Payment` and notifies the provider, just like the regular create flow

**`app/controllers/api/orders_controller.rb`**
- Added `rebook` action: `POST /api/orders/:id/rebook`
- Requires a client token; providers get 403
- Returns 422 if `scheduled_at` is missing
- Delegates ownership checks to the service, returning 403 if the client doesn't own the original order

**`config/routes.rb`**
- Added `post :rebook` as a member route on orders

**`spec/services/orders/rebook_service_spec.rb`** and **`spec/requests/api/orders_spec.rb`** *(new/updated)*
- Full test coverage for happy path, missing `scheduled_at`, wrong client, provider attempting rebook, and 404 — all 33 specs pass

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..c5c0b90 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       orders = scoped_orders
@@ -34,6 +34,29 @@ def create
       end
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      if params[:scheduled_at].blank?
+        return render_unprocessable(["Scheduled at is required"])
+      end
+
+      result = Orders::RebookService.new(
+        original_order: @order,
+        client: client,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: order_detail_json(result[:order]), status: :created
+      elsif result[:error] == "Forbidden"
+        render_forbidden
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
@@ -109,6 +132,10 @@ def order_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :notes)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/services/orders/rebook_service.rb b/affordance_order/app/services/orders/rebook_service.rb
new file mode 100644
index 0000000..2cdc8a1
--- /dev/null
+++ b/affordance_order/app/services/orders/rebook_service.rb
@@ -0,0 +1,48 @@
+module Orders
+  class RebookService
+    def initialize(original_order:, client:, params:)
+      @original_order = original_order
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @original_order.client == @client
+        return { success: false, error: "Forbidden" }
+      end
+
+      order = Order.new(
+        client: @client,
+        provider: @original_order.provider,
+        location: @original_order.location,
+        duration_minutes: @original_order.duration_minutes,
+        amount_cents: @original_order.amount_cents,
+        currency: @original_order.currency,
+        scheduled_at: @params[:scheduled_at],
+        notes: @params[:notes]
+      )
+
+      Order.transaction do
+        order.save!
+        Payment.create!(
+          order: order,
+          amount_cents: order.amount_cents,
+          currency: order.currency,
+          fee_cents: calculate_fee(order.amount_cents),
+          status: "pending"
+        )
+      end
+
+      NotificationService.notify(order.provider, :order_created, order_id: order.id)
+      { success: true, order: order }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
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
index b5e1bbb..d972c1d 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -180,4 +180,57 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/orders/:id/rebook" do
+    let(:original_order) do
+      create(:order, :completed, client: client, provider: provider,
+        location: "456 Oak Ave", duration_minutes: 60, amount_cents: 150_000)
+    end
+
+    it "creates a new order reusing provider, location, and duration" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("456 Oak Ave")
+      expect(body["duration_minutes"]).to eq(60)
+      expect(body["amount_cents"]).to eq(150_000)
+    end
+
+    it "returns 422 when scheduled_at is missing" do
+      post "/api/orders/#{original_order.id}/rebook",
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for a provider" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 403 when a different client tries to rebook" do
+      other_client = create(:client)
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for non-existent order" do
+      post "/api/orders/99999/rebook",
+        params: { scheduled_at: 7.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:not_found)
+    end
+  end
 end
diff --git a/affordance_order/spec/services/orders/rebook_service_spec.rb b/affordance_order/spec/services/orders/rebook_service_spec.rb
new file mode 100644
index 0000000..aa5e5a2
--- /dev/null
+++ b/affordance_order/spec/services/orders/rebook_service_spec.rb
@@ -0,0 +1,86 @@
+require "rails_helper"
+
+RSpec.describe Orders::RebookService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_order) do
+    create(:order,
+      client: client,
+      provider: provider,
+      location: "123 Main St",
+      duration_minutes: 90,
+      amount_cents: 200_000,
+      currency: "RUB",
+      state: "completed"
+    )
+  end
+
+  subject(:result) do
+    described_class.new(
+      original_order: original_order,
+      client: client,
+      params: { scheduled_at: 5.days.from_now, notes: "New notes" }
+    ).call
+  end
+
+  describe "#call" do
+    context "when the client owns the original order" do
+      it "creates a new order reusing provider, location, and duration" do
+        expect(result[:success]).to be true
+        order = result[:order]
+        expect(order.provider).to eq(provider)
+        expect(order.location).to eq("123 Main St")
+        expect(order.duration_minutes).to eq(90)
+        expect(order.client).to eq(client)
+        expect(order.state).to eq("pending")
+      end
+
+      it "uses the new scheduled_at" do
+        expect(result[:order].scheduled_at).to be_within(1.second).of(5.days.from_now)
+      end
+
+      it "creates a payment for the new order" do
+        expect { result }.to change(Payment, :count).by(1)
+        payment = result[:order].payment
+        expect(payment.status).to eq("pending")
+        expect(payment.amount_cents).to eq(200_000)
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=order_created")
+      end
+    end
+
+    context "when a different client tries to rebook" do
+      subject(:result) do
+        described_class.new(
+          original_order: original_order,
+          client: other_client,
+          params: { scheduled_at: 5.days.from_now }
+        ).call
+      end
+
+      it "returns forbidden error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Forbidden")
+      end
+    end
+
+    context "when scheduled_at is missing" do
+      subject(:result) do
+        described_class.new(
+          original_order: original_order,
+          client: client,
+          params: { scheduled_at: nil }
+        ).call
+      end
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+    end
+  end
+end
```
