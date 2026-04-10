# Experiment: 02-rebook-feature
# App: order | Model: sonnet | Run: 1
# Branch: experiment/02-rebook-feature/order/sonnet/run-1

---

## Claude Output

The rebook feature is implemented and committed. Here's a summary of what was added:

### Changes

**`app/services/orders/rebook_service.rb`** (new)
- `Orders::RebookService` takes the original order, the requesting client, and params
- Verifies the client owns the original order (returns a 403-friendly error otherwise)
- Creates a new `pending` order copying `provider`, `location`, `duration_minutes`, `currency` and optionally `notes` / `amount_cents` (can be overridden by the caller)
- Creates the associated `Payment` with a 10% fee in the same transaction
- Notifies the provider via `NotificationService`

**`app/controllers/api/orders_controller.rb`**
- Added `rebook` to the `before_action :set_order` list
- New `rebook` action: client-only, requires `scheduled_at`, delegates to `RebookService`, returns 201 on success

**`config/routes.rb`**
- Added `post :rebook` as a member route under `resources :orders`

**`spec/services/orders/rebook_service_spec.rb`** (new) + **`spec/requests/api/orders_spec.rb`**
- Full unit coverage of the service (valid params, field overrides, wrong client, missing scheduled_at)
- Request specs covering 201 success, 422 missing field, 403 provider attempt, 403 wrong client, 404 unknown order

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..38453be 100644
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
+      elsif result[:errors]
+        render_unprocessable(result[:errors].full_messages)
+      else
+        render json: { error: result[:error] }, status: :forbidden
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
+      params.permit(:scheduled_at, :notes, :amount_cents)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/services/orders/rebook_service.rb b/affordance_order/app/services/orders/rebook_service.rb
new file mode 100644
index 0000000..d76c8c2
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
+        return { success: false, error: "You can only rebook your own orders" }
+      end
+
+      new_order = Order.new(
+        client: @client,
+        provider: @original_order.provider,
+        location: @original_order.location,
+        duration_minutes: @original_order.duration_minutes,
+        scheduled_at: @params[:scheduled_at],
+        notes: @params.fetch(:notes, @original_order.notes),
+        amount_cents: @params.fetch(:amount_cents, @original_order.amount_cents),
+        currency: @original_order.currency
+      )
+
+      Order.transaction do
+        new_order.save!
+        Payment.create!(
+          order: new_order,
+          amount_cents: new_order.amount_cents,
+          currency: new_order.currency,
+          fee_cents: calculate_fee(new_order.amount_cents),
+          status: "pending"
+        )
+      end
+
+      NotificationService.notify(new_order.provider, :order_created, order_id: new_order.id)
+      { success: true, order: new_order }
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
index b5e1bbb..22e4c53 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -166,6 +166,65 @@
     end
   end
 
+  describe "POST /api/orders/:id/rebook" do
+    let(:original_order) do
+      create(:order, :completed,
+        client: client,
+        provider: provider,
+        location: "456 Oak Ave",
+        duration_minutes: 90,
+        amount_cents: 200_000,
+        currency: "RUB"
+      )
+    end
+
+    it "creates a new order reusing provider, location, and duration" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("456 Oak Ave")
+      expect(body["duration_minutes"]).to eq(90)
+    end
+
+    it "returns 422 when scheduled_at is missing" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: {},
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 when a provider attempts to rebook" do
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 403 when a different client tries to rebook" do
+      other_client = create(:client)
+      post "/api/orders/#{original_order.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
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
index 0000000..b59a91c
--- /dev/null
+++ b/affordance_order/spec/services/orders/rebook_service_spec.rb
@@ -0,0 +1,141 @@
+require "rails_helper"
+
+RSpec.describe Orders::RebookService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_order) do
+    create(:order, :completed,
+      client: client,
+      provider: provider,
+      location: "456 Oak Ave",
+      duration_minutes: 90,
+      amount_cents: 200_000,
+      currency: "RUB",
+      notes: "Original notes"
+    )
+  end
+  let(:new_scheduled_at) { 5.days.from_now }
+
+  subject(:result) do
+    described_class.new(
+      original_order: original_order,
+      client: client,
+      params: { scheduled_at: new_scheduled_at }
+    ).call
+  end
+
+  describe "#call" do
+    context "with valid params" do
+      it "returns success" do
+        expect(result[:success]).to be true
+      end
+
+      it "creates a new order in pending state" do
+        original_order # ensure it exists before counting
+        expect { result }.to change(Order, :count).by(1)
+        expect(result[:order].state).to eq("pending")
+      end
+
+      it "reuses the provider from the original order" do
+        expect(result[:order].provider).to eq(provider)
+      end
+
+      it "reuses the location from the original order" do
+        expect(result[:order].location).to eq("456 Oak Ave")
+      end
+
+      it "reuses the duration from the original order" do
+        expect(result[:order].duration_minutes).to eq(90)
+      end
+
+      it "uses the new scheduled_at" do
+        expect(result[:order].scheduled_at).to be_within(1.second).of(new_scheduled_at)
+      end
+
+      it "reuses the notes from the original order by default" do
+        expect(result[:order].notes).to eq("Original notes")
+      end
+
+      it "reuses the amount_cents from the original order by default" do
+        expect(result[:order].amount_cents).to eq(200_000)
+      end
+
+      it "creates a pending payment with 10% fee" do
+        expect { result }.to change(Payment, :count).by(1)
+        payment = result[:order].payment
+        expect(payment.status).to eq("pending")
+        expect(payment.fee_cents).to eq(20_000)
+        expect(payment.amount_cents).to eq(200_000)
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=order_created")
+      end
+    end
+
+    context "when overriding optional fields" do
+      subject(:result) do
+        described_class.new(
+          original_order: original_order,
+          client: client,
+          params: {
+            scheduled_at: new_scheduled_at,
+            notes: "New notes",
+            amount_cents: 250_000
+          }
+        ).call
+      end
+
+      it "uses the overridden notes" do
+        expect(result[:order].notes).to eq("New notes")
+      end
+
+      it "uses the overridden amount_cents" do
+        expect(result[:order].amount_cents).to eq(250_000)
+      end
+    end
+
+    context "when client does not own the original order" do
+      subject(:result) do
+        described_class.new(
+          original_order: original_order,
+          client: other_client,
+          params: { scheduled_at: new_scheduled_at }
+        ).call
+      end
+
+      it "returns failure" do
+        expect(result[:success]).to be false
+      end
+
+      it "returns a permission error" do
+        expect(result[:error]).to eq("You can only rebook your own orders")
+      end
+
+      it "does not create a new order" do
+        original_order # ensure it exists before counting
+        expect { result }.not_to change(Order, :count)
+      end
+    end
+
+    context "with missing scheduled_at" do
+      subject(:result) do
+        described_class.new(
+          original_order: original_order,
+          client: client,
+          params: {}
+        ).call
+      end
+
+      it "returns failure" do
+        expect(result[:success]).to be false
+      end
+
+      it "returns validation errors" do
+        expect(result[:errors]).to be_present
+      end
+    end
+  end
+end
```
