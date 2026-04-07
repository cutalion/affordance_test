# Experiment: 04-bulk-booking
# App: order | Model: opus | Run: 3
# Branch: experiment/04-bulk-booking/order/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**New endpoint**: `POST /api/orders/bulk_create`

**Parameters**:
- `provider_id` - target provider
- `scheduled_at` - first session time
- `count` - number of sessions (2-5, default 5)
- `interval_days` - days between sessions (default 7)
- Standard order fields: `duration_minutes`, `amount_cents`, `currency`, `location`, `notes`

**Key design decisions**:
- All orders + payments created atomically in a single transaction — if any fails, all roll back
- Single notification sent to the provider with all order IDs
- Returns array of full order detail objects
- Reuses the same fee calculation (10%) as single-order creation

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..67ad3dc 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -34,6 +34,26 @@ def create
       end
     end
 
+    def bulk_create
+      client = current_client!
+      return if performed?
+
+      provider = Provider.find_by(id: params[:provider_id])
+      return render_not_found unless provider
+
+      result = Orders::BulkCreateService.new(
+        client: client,
+        provider: provider,
+        params: bulk_order_params
+      ).call
+
+      if result[:success]
+        render json: result[:orders].map { |o| order_detail_json(o) }, status: :created
+      else
+        render_unprocessable(result[:errors])
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
@@ -109,6 +129,10 @@ def order_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def bulk_order_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency, :count, :interval_days)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/services/orders/bulk_create_service.rb b/affordance_order/app/services/orders/bulk_create_service.rb
new file mode 100644
index 0000000..4a3033d
--- /dev/null
+++ b/affordance_order/app/services/orders/bulk_create_service.rb
@@ -0,0 +1,71 @@
+module Orders
+  class BulkCreateService
+    MAX_SESSIONS = 5
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      count = (@params[:count] || MAX_SESSIONS).to_i
+      interval_days = (@params[:interval_days] || 7).to_i
+
+      if count < 2 || count > MAX_SESSIONS
+        return { success: false, errors: ["Count must be between 2 and #{MAX_SESSIONS}"] }
+      end
+
+      if interval_days < 1
+        return { success: false, errors: ["Interval days must be at least 1"] }
+      end
+
+      base_scheduled_at = @params[:scheduled_at]
+      unless base_scheduled_at.present?
+        return { success: false, errors: ["Scheduled at is required"] }
+      end
+
+      base_time = base_scheduled_at.is_a?(String) ? Time.zone.parse(base_scheduled_at) : base_scheduled_at
+
+      orders = []
+
+      Order.transaction do
+        count.times do |i|
+          scheduled_at = base_time + (i * interval_days).days
+
+          order = Order.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: scheduled_at,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB"
+          )
+
+          Payment.create!(
+            order: order,
+            amount_cents: order.amount_cents,
+            currency: order.currency,
+            fee_cents: calculate_fee(order.amount_cents),
+            status: "pending"
+          )
+
+          orders << order
+        end
+      end
+
+      NotificationService.notify(@provider, :bulk_order_created, order_ids: orders.map(&:id).join(","))
+      { success: true, orders: orders }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors.full_messages }
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
index 9c38c15..e04e476 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :orders, only: [:index, :show, :create] do
+      collection do
+        post :bulk_create
+      end
       member do
         patch :confirm
         patch :start
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..668a6cf 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -180,4 +180,64 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/orders/bulk_create" do
+    let(:bulk_params) do
+      {
+        provider_id: provider.id,
+        scheduled_at: 3.days.from_now.iso8601,
+        duration_minutes: 120,
+        amount_cents: 350_000,
+        currency: "RUB",
+        count: 5,
+        interval_days: 7
+      }
+    end
+
+    it "creates 5 orders in a single call" do
+      expect {
+        post "/api/orders/bulk_create", params: bulk_params, headers: auth_headers(client)
+      }.to change(Order, :count).by(5)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.size).to eq(5)
+      expect(body.map { |o| o["state"] }.uniq).to eq(["pending"])
+    end
+
+    it "schedules orders at weekly intervals" do
+      post "/api/orders/bulk_create", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body.map { |o| Time.zone.parse(o["scheduled_at"]) }
+      (1...times.size).each do |i|
+        expect(times[i] - times[i - 1]).to be_within(1.second).of(7.days)
+      end
+    end
+
+    it "creates payments for all orders" do
+      expect {
+        post "/api/orders/bulk_create", params: bulk_params, headers: auth_headers(client)
+      }.to change(Payment, :count).by(5)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/orders/bulk_create", params: bulk_params, headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for non-existent provider" do
+      post "/api/orders/bulk_create", params: bulk_params.merge(provider_id: 99999), headers: auth_headers(client)
+      expect(response).to have_http_status(:not_found)
+    end
+
+    it "returns errors for invalid count" do
+      post "/api/orders/bulk_create", params: bulk_params.merge(count: 10), headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns errors for missing fields" do
+      post "/api/orders/bulk_create", params: { provider_id: provider.id, count: 3 }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
diff --git a/affordance_order/spec/services/orders/bulk_create_service_spec.rb b/affordance_order/spec/services/orders/bulk_create_service_spec.rb
new file mode 100644
index 0000000..99f105d
--- /dev/null
+++ b/affordance_order/spec/services/orders/bulk_create_service_spec.rb
@@ -0,0 +1,120 @@
+require "rails_helper"
+
+RSpec.describe Orders::BulkCreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:base_time) { 3.days.from_now }
+  let(:valid_params) do
+    {
+      scheduled_at: base_time,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 350_000,
+      currency: "RUB",
+      count: 5,
+      interval_days: 7
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }
+
+  describe "#call" do
+    context "with valid params" do
+      it "creates 5 orders" do
+        expect { result }.to change(Order, :count).by(5)
+        expect(result[:success]).to be true
+        expect(result[:orders].size).to eq(5)
+      end
+
+      it "schedules orders at weekly intervals" do
+        orders = result[:orders]
+        orders.each_with_index do |order, i|
+          expected_time = base_time + (i * 7).days
+          expect(order.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "creates a payment for each order" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:orders].each do |order|
+          payment = order.payment
+          expect(payment.status).to eq("pending")
+          expect(payment.fee_cents).to eq(35_000)
+          expect(payment.amount_cents).to eq(350_000)
+        end
+      end
+
+      it "notifies the provider once" do
+        result
+        expect(read_notification_log).to include("event=bulk_order_created")
+      end
+
+      it "creates all orders in pending state" do
+        result[:orders].each do |order|
+          expect(order.state).to eq("pending")
+        end
+      end
+    end
+
+    context "with custom count and interval" do
+      let(:valid_params) { super().merge(count: 3, interval_days: 14) }
+
+      it "creates the requested number of orders" do
+        expect { result }.to change(Order, :count).by(3)
+      end
+
+      it "uses the custom interval" do
+        orders = result[:orders]
+        expect(orders[1].scheduled_at).to be_within(1.second).of(base_time + 14.days)
+        expect(orders[2].scheduled_at).to be_within(1.second).of(base_time + 28.days)
+      end
+    end
+
+    context "with defaults" do
+      let(:valid_params) { super().except(:count, :interval_days) }
+
+      it "defaults to 5 sessions with 7-day interval" do
+        expect { result }.to change(Order, :count).by(5)
+        orders = result[:orders]
+        expect(orders.last.scheduled_at).to be_within(1.second).of(base_time + 28.days)
+      end
+    end
+
+    context "with invalid count" do
+      let(:valid_params) { super().merge(count: 10) }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to include(/Count must be between/)
+      end
+    end
+
+    context "with count of 1" do
+      let(:valid_params) { super().merge(count: 1) }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to include(/Count must be between/)
+      end
+    end
+
+    context "with missing scheduled_at" do
+      let(:valid_params) { super().merge(scheduled_at: nil) }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to include(/Scheduled at is required/)
+      end
+    end
+
+    context "with invalid order params" do
+      let(:valid_params) { super().merge(amount_cents: nil, duration_minutes: nil) }
+
+      it "rolls back all orders on failure" do
+        expect { result }.not_to change(Order, :count)
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
