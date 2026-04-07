# Experiment: 04-bulk-booking
# App: order | Model: sonnet | Run: 3
# Branch: experiment/04-bulk-booking/order/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**New endpoint:** `POST /api/orders/bulk`

**Files changed:**
- `config/routes.rb` — added `post :bulk, on: :collection` to orders resources
- `app/services/orders/bulk_create_service.rb` — new service that creates 5 orders in a single transaction, scheduled 1 week apart
- `app/controllers/api/orders_controller.rb` — added `bulk` action
- `spec/requests/api/orders_spec.rb` — 6 tests covering the new endpoint

**API contract:**
```json
POST /api/orders/bulk
{
  "provider_id": 1,
  "first_session_at": "2026-04-14T10:00:00Z",
  "duration_minutes": 60,
  "amount_cents": 200000,
  "currency": "RUB"
}
```
Returns an array of 5 order objects. Rolls back all if any session fails validation.

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..693330f 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -34,6 +34,26 @@ def create
       end
     end
 
+    def bulk
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
+      params.permit(:first_session_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/services/orders/bulk_create_service.rb b/affordance_order/app/services/orders/bulk_create_service.rb
new file mode 100644
index 0000000..e324661
--- /dev/null
+++ b/affordance_order/app/services/orders/bulk_create_service.rb
@@ -0,0 +1,71 @@
+module Orders
+  class BulkCreateService
+    SESSION_COUNT = 5
+    SESSION_INTERVAL = 1.week
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      unless first_session_at
+        placeholder = Order.new(client: @client, provider: @provider, scheduled_at: nil,
+                                duration_minutes: @params[:duration_minutes],
+                                amount_cents: @params[:amount_cents], currency: @params[:currency] || "RUB")
+        placeholder.valid?
+        placeholder.errors.add(:first_session_at, "can't be blank") unless @params[:first_session_at].present?
+        return { success: false, errors: placeholder.errors }
+      end
+
+      orders = SESSION_COUNT.times.map do |i|
+        Order.new(
+          client: @client,
+          provider: @provider,
+          scheduled_at: first_session_at + i * SESSION_INTERVAL,
+          duration_minutes: @params[:duration_minutes],
+          location: @params[:location],
+          notes: @params[:notes],
+          amount_cents: @params[:amount_cents],
+          currency: @params[:currency] || "RUB"
+        )
+      end
+
+      orders.each do |order|
+        unless order.valid?
+          return { success: false, errors: order.errors }
+        end
+      end
+
+      Order.transaction do
+        orders.each do |order|
+          order.save!
+          Payment.create!(
+            order: order,
+            amount_cents: order.amount_cents,
+            currency: order.currency,
+            fee_cents: calculate_fee(order.amount_cents),
+            status: "pending"
+          )
+        end
+      end
+
+      orders.each { |order| NotificationService.notify(@provider, :order_created, order_id: order.id) }
+      { success: true, orders: orders }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def first_session_at
+      return nil unless @params[:first_session_at].present?
+      @first_session_at ||= Time.zone.parse(@params[:first_session_at].to_s)
+    end
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..a6a293e 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -11,6 +11,7 @@
     end
 
     resources :orders, only: [:index, :show, :create] do
+      post :bulk, on: :collection
       member do
         patch :confirm
         patch :start
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..38cb924 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -93,6 +93,56 @@
     end
   end
 
+  describe "POST /api/orders/bulk" do
+    let(:bulk_params) do
+      {
+        provider_id: provider.id,
+        first_session_at: 7.days.from_now.iso8601,
+        duration_minutes: 60,
+        amount_cents: 200_000,
+        currency: "RUB"
+      }
+    end
+
+    it "creates 5 weekly sessions for a client" do
+      post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      body.each { |o| expect(o["state"]).to eq("pending") }
+    end
+
+    it "schedules sessions one week apart" do
+      post "/api/orders/bulk", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body.map { |o| Time.parse(o["scheduled_at"]) }.sort
+      (0..3).each do |i|
+        expect(times[i + 1] - times[i]).to be_within(1.minute).of(1.week)
+      end
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
+    it "returns validation errors for missing fields" do
+      post "/api/orders/bulk", params: { provider_id: provider.id }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "creates no orders if any session is invalid" do
+      expect {
+        post "/api/orders/bulk", params: { provider_id: provider.id }, headers: auth_headers(client)
+      }.not_to change(Order, :count)
+    end
+  end
+
   describe "PATCH /api/orders/:id/confirm" do
     let(:order) { create(:order, client: client, provider: provider) }
 
```
