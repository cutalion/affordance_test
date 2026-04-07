# Experiment: 02-rebook-feature
# App: order | Model: sonnet | Run: 3
# Branch: experiment/02-rebook-feature/order/sonnet/run-3

---

## Claude Output

The rebook feature has been implemented and committed. Here's a summary of what was added:

### Changes

**`app/services/orders/rebook_service.rb`** (new)
- Verifies the requesting client owns the source order
- Delegates to `CreateService`, copying `provider`, `location`, `duration_minutes`, `amount_cents`, and `currency` from the source order
- Accepts a new `scheduled_at` (and optionally `notes`) from the client

**`app/controllers/api/orders_controller.rb`**
- Added `rebook` action that requires the client role and a `scheduled_at` param
- Returns the new order as `201 Created` on success
- Returns `422` if `scheduled_at` is missing or the client doesn't own the source order
- Returns `403` if a provider tries to use it

**`config/routes.rb`**
- Added `POST /api/orders/:id/rebook`

**`spec/services/orders/rebook_service_spec.rb`** & **`spec/requests/api/orders_spec.rb`** (new/updated)
- Full coverage: happy path, wrong client, missing param, provider access denied, unknown order — all 35 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..413dca5 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class OrdersController < BaseController
-    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_order, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       orders = scoped_orders
@@ -34,6 +34,28 @@ def create
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
+        client: client,
+        source_order: @order,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: order_detail_json(result[:order]), status: :created
+      else
+        errors = result[:errors]&.full_messages || [result[:error]]
+        render_unprocessable(errors)
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
@@ -109,6 +131,10 @@ def order_params
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
index 0000000..2fac184
--- /dev/null
+++ b/affordance_order/app/services/orders/rebook_service.rb
@@ -0,0 +1,28 @@
+module Orders
+  class RebookService
+    def initialize(client:, source_order:, params:)
+      @client = client
+      @source_order = source_order
+      @params = params
+    end
+
+    def call
+      unless @source_order.client == @client
+        return { success: false, error: "Order not found" }
+      end
+
+      CreateService.new(
+        client: @client,
+        provider: @source_order.provider,
+        params: {
+          scheduled_at: @params[:scheduled_at],
+          duration_minutes: @source_order.duration_minutes,
+          location: @source_order.location,
+          notes: @params[:notes],
+          amount_cents: @source_order.amount_cents,
+          currency: @source_order.currency
+        }
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
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..3c72fb5 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -166,6 +166,52 @@
     end
   end
 
+  describe "POST /api/orders/:id/rebook" do
+    let(:source_order) do
+      create(:order, :completed,
+        client: client,
+        provider: provider,
+        duration_minutes: 90,
+        location: "456 Oak Ave",
+        amount_cents: 200_000,
+        currency: "RUB"
+      )
+    end
+
+    let(:rebook_params) { { scheduled_at: 7.days.from_now.iso8601 } }
+
+    it "creates a new order reusing provider, location, and duration" do
+      post "/api/orders/#{source_order.id}/rebook", params: rebook_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("456 Oak Ave")
+      expect(body["duration_minutes"]).to eq(90)
+    end
+
+    it "returns 422 without scheduled_at" do
+      post "/api/orders/#{source_order.id}/rebook", headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for a provider" do
+      post "/api/orders/#{source_order.id}/rebook", params: rebook_params, headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 422 when client does not own the source order" do
+      other_client = create(:client)
+      post "/api/orders/#{source_order.id}/rebook", params: rebook_params, headers: auth_headers(other_client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 404 for unknown order" do
+      post "/api/orders/99999/rebook", params: rebook_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:not_found)
+    end
+  end
+
   describe "PATCH /api/orders/:id/reject" do
     let(:order) { create(:order, :confirmed, client: client, provider: provider) }
 
diff --git a/affordance_order/spec/services/orders/rebook_service_spec.rb b/affordance_order/spec/services/orders/rebook_service_spec.rb
new file mode 100644
index 0000000..ef92243
--- /dev/null
+++ b/affordance_order/spec/services/orders/rebook_service_spec.rb
@@ -0,0 +1,77 @@
+require "rails_helper"
+
+RSpec.describe Orders::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:source_order) do
+    create(:order, :completed,
+      client: client,
+      provider: provider,
+      duration_minutes: 90,
+      location: "123 Main St",
+      amount_cents: 250_000,
+      currency: "RUB"
+    )
+  end
+
+  let(:new_scheduled_at) { 5.days.from_now }
+
+  subject(:result) do
+    described_class.new(
+      client: client,
+      source_order: source_order,
+      params: { scheduled_at: new_scheduled_at }
+    ).call
+  end
+
+  describe "#call" do
+    context "when the client owns the source order" do
+      it "creates a new order in pending state" do
+        expect(result[:success]).to be true
+        expect(result[:order].state).to eq("pending")
+      end
+
+      it "reuses provider from the source order" do
+        expect(result[:order].provider).to eq(provider)
+      end
+
+      it "reuses location from the source order" do
+        expect(result[:order].location).to eq("123 Main St")
+      end
+
+      it "reuses duration from the source order" do
+        expect(result[:order].duration_minutes).to eq(90)
+      end
+
+      it "reuses amount and currency from the source order" do
+        expect(result[:order].amount_cents).to eq(250_000)
+        expect(result[:order].currency).to eq("RUB")
+      end
+
+      it "uses the new scheduled_at" do
+        expect(result[:order].scheduled_at).to be_within(1.second).of(new_scheduled_at)
+      end
+
+      it "creates a payment for the new order" do
+        expect { result }.to change(Payment, :count).by(1)
+      end
+    end
+
+    context "when the client does not own the source order" do
+      let(:other_client) { create(:client) }
+
+      subject(:result) do
+        described_class.new(
+          client: other_client,
+          source_order: source_order,
+          params: { scheduled_at: new_scheduled_at }
+        ).call
+      end
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to be_present
+      end
+    end
+  end
+end
```
