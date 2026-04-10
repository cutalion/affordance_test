# Experiment: 04-bulk-booking
# App: order | Model: sonnet | Run: 1
# Branch: experiment/04-bulk-booking/order/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**`POST /api/orders/bulk`** — creates 5 weekly recurring sessions in a single API call.

**Request params:**
```json
{
  "provider_id": 1,
  "first_scheduled_at": "2026-04-14T10:00:00Z",
  "duration_minutes": 120,
  "amount_cents": 350000,
  "currency": "RUB",
  "location": "...",
  "notes": "..."
}
```

**Response:** array of 5 order detail objects (HTTP 201).

**Files changed:**
- `app/services/orders/bulk_create_service.rb` — new service, creates all 5 orders + payments in one transaction, notifies provider once
- `app/controllers/api/orders_controller.rb` — added `bulk_create` action
- `config/routes.rb` — added `POST /api/orders/bulk` collection route

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..5fed861 100644
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
+      params.permit(:first_scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: order_detail_json(result[:order])
diff --git a/affordance_order/app/services/orders/bulk_create_service.rb b/affordance_order/app/services/orders/bulk_create_service.rb
new file mode 100644
index 0000000..107ebe8
--- /dev/null
+++ b/affordance_order/app/services/orders/bulk_create_service.rb
@@ -0,0 +1,59 @@
+module Orders
+  class BulkCreateService
+    SESSIONS_COUNT = 5
+    INTERVAL = 1.week
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      orders = []
+
+      Order.transaction do
+        SESSIONS_COUNT.times do |i|
+          scheduled_at = first_scheduled_at + (i * INTERVAL)
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
+            fee_cents: calculate_fee(order.amount_cents),
+            status: "pending"
+          )
+
+          orders << order
+        end
+      end
+
+      NotificationService.notify(@provider, :bulk_order_created, order_ids: orders.map(&:id))
+      { success: true, orders: orders }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def first_scheduled_at
+      @first_scheduled_at ||= Time.zone.parse(@params[:first_scheduled_at].to_s)
+    end
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/affordance_order/config/routes.rb b/affordance_order/config/routes.rb
index 9c38c15..d1f6b25 100644
--- a/affordance_order/config/routes.rb
+++ b/affordance_order/config/routes.rb
@@ -11,6 +11,7 @@
     end
 
     resources :orders, only: [:index, :show, :create] do
+      post :bulk, on: :collection, action: :bulk_create
       member do
         patch :confirm
         patch :start
```
