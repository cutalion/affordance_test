# Experiment: 04-bulk-booking
# App: order | Model: sonnet | Run: 2
# Branch: experiment/04-bulk-booking/order/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**New endpoint:** `POST /api/orders/bulk`

**Params:**
- `provider_id` (required)
- `scheduled_at` — first session date/time (required)
- `duration_minutes`, `amount_cents`, `currency`, `location`, `notes` — same as single order
- `sessions_count` — number of sessions (default: 5)
- `interval_days` — days between sessions (default: 7 for weekly)

**Behavior:**
- Creates all orders atomically in a single transaction (all succeed or none do)
- Creates a payment for each order (10% fee, same as single orders)
- Notifies the provider for each order created
- Returns an array of order detail objects with HTTP 201

**Files changed:**
- `app/services/orders/bulk_create_service.rb` — new service
- `app/controllers/api/orders_controller.rb` — `bulk_create` action + `bulk_order_params`
- `config/routes.rb` — `POST /api/orders/bulk` route
- `spec/requests/api/orders_spec.rb` — 9 new request specs (all passing)

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..dda61dd 100644
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
+        render_unprocessable(result[:errors].full_messages)
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
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency, :sessions_count, :interval_days)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/services/orders/bulk_create_service.rb b/affordance_order/app/services/orders/bulk_create_service.rb
new file mode 100644
index 0000000..360a4d7
--- /dev/null
+++ b/affordance_order/app/services/orders/bulk_create_service.rb
@@ -0,0 +1,58 @@
+module Orders
+  class BulkCreateService
+    SESSIONS_COUNT = 5
+    INTERVAL_DAYS = 7
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      sessions_count = (@params[:sessions_count] || SESSIONS_COUNT).to_i
+      interval_days = (@params[:interval_days] || INTERVAL_DAYS).to_i
+      first_scheduled_at = @params[:scheduled_at]
+
+      orders = []
+
+      Order.transaction do
+        base_time = first_scheduled_at.present? ? Time.parse(first_scheduled_at.to_s) : nil
+
+      sessions_count.times do |i|
+          scheduled_at = base_time ? base_time + (interval_days * i).days : nil
+
+          order = Order.new(
+            client: @client,
+            provider: @provider,
+            scheduled_at: scheduled_at,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB"
+          )
+          order.save!
+
+          Payment.create!(
+            order: order,
+            amount_cents: order.amount_cents,
+            currency: order.currency,
+            fee_cents: (order.amount_cents * 0.1).to_i,
+            status: "pending"
+          )
+
+          orders << order
+        end
+      end
+
+      orders.each do |order|
+        NotificationService.notify(@provider, :order_created, order_id: order.id)
+      end
+
+      { success: true, orders: orders }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..db42ece 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -10,6 +10,7 @@
       patch :default, on: :member, action: :set_default
     end
 
+    post "orders/bulk", to: "orders#bulk_create"
     resources :orders, only: [:index, :show, :create] do
       member do
         patch :confirm
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..6ed8be5 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -93,6 +93,82 @@
     end
   end
 
+  describe "POST /api/orders/bulk" do
+    let(:bulk_params) do
+      {
+        provider_id: provider.id,
+        scheduled_at: 3.days.from_now.iso8601,
+        duration_minutes: 60,
+        amount_cents: 200_000,
+        currency: "RUB"
+      }
+    end
+
+    it "creates 5 weekly sessions by default" do
+      expect {
+        post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      }.to change(Order, :count).by(5)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      expect(body.map { |o| o["state"] }).to all(eq("pending"))
+    end
+
+    it "schedules sessions one week apart" do
+      post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+
+      dates = body.map { |o| Time.parse(o["scheduled_at"]) }
+      gaps = dates.each_cons(2).map { |a, b| (b - a).to_i }
+      expect(gaps).to all(eq(7.days.to_i))
+    end
+
+    it "creates a payment for each session" do
+      expect {
+        post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      }.to change(Payment, :count).by(5)
+    end
+
+    it "respects custom sessions_count" do
+      post "/api/orders/bulk", params: bulk_params.merge(sessions_count: 3), headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(3)
+    end
+
+    it "respects custom interval_days" do
+      post "/api/orders/bulk", params: bulk_params.merge(interval_days: 14), headers: auth_headers(client)
+      body = JSON.parse(response.body)
+
+      dates = body.map { |o| Time.parse(o["scheduled_at"]) }
+      gaps = dates.each_cons(2).map { |a, b| (b - a).to_i }
+      expect(gaps).to all(eq(14.days.to_i))
+    end
+
+    it "returns 403 for provider" do
+      post "/api/orders/bulk", params: bulk_params, headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for non-existent provider" do
+      post "/api/orders/bulk", params: bulk_params.merge(provider_id: 99999), headers: auth_headers(client)
+      expect(response).to have_http_status(:not_found)
+    end
+
+    it "returns 401 without auth" do
+      post "/api/orders/bulk", params: bulk_params
+      expect(response).to have_http_status(:unauthorized)
+    end
+
+    it "creates no orders when validation fails" do
+      expect {
+        post "/api/orders/bulk", params: { provider_id: provider.id }, headers: auth_headers(client)
+      }.not_to change(Order, :count)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/orders/:id/confirm" do
     let(:order) { create(:order, client: client, provider: provider) }
 
```
