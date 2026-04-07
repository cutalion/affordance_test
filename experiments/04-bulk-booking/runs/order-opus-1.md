# Experiment: 04-bulk-booking
# App: order | Model: opus | Run: 1
# Branch: experiment/04-bulk-booking/order/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**New endpoint:** `POST /api/orders/bulk`

**Parameters:**
- `provider_id` — the provider for all sessions
- `scheduled_at` — date/time of the first session
- `duration_minutes`, `amount_cents`, `currency`, `location`, `notes` — same as single order creation
- `count` — number of sessions (1-5, defaults to 5, capped at 5)
- `recurrence` — `weekly` (default), `daily`, or `biweekly`

**Key behaviors:**
- All orders + payments created atomically in a single DB transaction — if any fails, all roll back
- Each order gets its own payment with the standard 10% fee
- Returns an array of order detail objects with status 201
- Only clients can call it (providers get 403)
- Notifications sent to the provider for each created order

**Files changed:**
- `app/services/orders/bulk_create_service.rb` — new service
- `app/controllers/api/orders_controller.rb` — new `bulk_create` action
- `config/routes.rb` — added `POST /api/orders/bulk` route
- `spec/requests/api/orders_spec.rb` — 7 new tests (all passing)

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..16165f9 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -34,6 +34,28 @@ def create
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
+        params: order_params,
+        recurrence: params[:recurrence] || :weekly,
+        count: params[:count] || 5
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
diff --git a/affordance_order/app/services/orders/bulk_create_service.rb b/affordance_order/app/services/orders/bulk_create_service.rb
new file mode 100644
index 0000000..a271721
--- /dev/null
+++ b/affordance_order/app/services/orders/bulk_create_service.rb
@@ -0,0 +1,72 @@
+module Orders
+  class BulkCreateService
+    MAX_SESSIONS = 5
+
+    def initialize(client:, provider:, params:, recurrence: :weekly, count: MAX_SESSIONS)
+      @client = client
+      @provider = provider
+      @params = params
+      @recurrence = recurrence
+      @count = [count.to_i, MAX_SESSIONS].min
+    end
+
+    def call
+      orders = []
+
+      Order.transaction do
+        @count.times do |i|
+          scheduled_at = calculate_scheduled_at(i)
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
+      orders.each do |order|
+        NotificationService.notify(@provider, :order_created, order_id: order.id)
+      end
+
+      { success: true, orders: orders }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def calculate_scheduled_at(index)
+      base = Time.zone.parse(@params[:scheduled_at].to_s)
+      case @recurrence.to_sym
+      when :weekly
+        base + index.weeks
+      when :daily
+        base + index.days
+      when :biweekly
+        base + (index * 2).weeks
+      else
+        base + index.weeks
+      end
+    end
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..5feb229 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :orders, only: [:index, :show, :create] do
+      collection do
+        post :bulk, action: :bulk_create
+      end
       member do
         patch :confirm
         patch :start
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..346eb01 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -93,6 +93,73 @@
     end
   end
 
+  describe "POST /api/orders/bulk" do
+    let(:bulk_params) do
+      {
+        provider_id: provider.id,
+        scheduled_at: 3.days.from_now.iso8601,
+        duration_minutes: 120,
+        amount_cents: 350_000,
+        currency: "RUB",
+        count: 5,
+        recurrence: "weekly"
+      }
+    end
+
+    it "creates 5 weekly recurring orders" do
+      post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      expect(body.map { |o| o["state"] }).to all(eq("pending"))
+    end
+
+    it "spaces orders one week apart" do
+      post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body.map { |o| Time.zone.parse(o["scheduled_at"]) }
+      (1...times.length).each do |i|
+        expect(times[i] - times[i - 1]).to be_within(1.minute).of(1.week)
+      end
+    end
+
+    it "creates a payment for each order" do
+      expect {
+        post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      }.to change(Payment, :count).by(5)
+    end
+
+    it "creates all orders in a single transaction (rolls back on failure)" do
+      post "/api/orders/bulk", params: bulk_params.merge(amount_cents: nil), headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+      expect(Order.count).to eq(0)
+    end
+
+    it "caps count at 5" do
+      post "/api/orders/bulk", params: bulk_params.merge(count: 10), headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
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
+    it "supports daily recurrence" do
+      post "/api/orders/bulk", params: bulk_params.merge(recurrence: "daily", count: 3), headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(3)
+      times = body.map { |o| Time.zone.parse(o["scheduled_at"]) }
+      expect(times[1] - times[0]).to be_within(1.minute).of(1.day)
+    end
+  end
+
   describe "PATCH /api/orders/:id/confirm" do
     let(:order) { create(:order, client: client, provider: provider) }
 
```
