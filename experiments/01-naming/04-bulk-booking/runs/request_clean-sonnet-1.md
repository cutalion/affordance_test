# Experiment: 04-bulk-booking
# App: request_clean | Model: sonnet | Run: 1
# Branch: experiment/04-bulk-booking/request_clean/sonnet/run-1

---

## Claude Output

Done. Here's what was added:

**`POST /api/requests/bulk_create`** — clients only

Params:
| Field | Required | Default |
|-------|----------|---------|
| `provider_id` | yes | — |
| `scheduled_at` | yes | — |
| `duration_minutes` | yes | — |
| `amount_cents` | yes | — |
| `currency` | no | `"RUB"` |
| `sessions_count` | no | `5` |
| `interval_days` | no | `7` (weekly) |

Response: array of 5 request detail objects, HTTP 201.

**Implementation details:**
- `Requests::BulkCreateService` (`app/services/requests/bulk_create_service.rb`) — creates all sessions + payments in a single `Request.transaction`. Any validation failure rolls back everything.
- Sessions are spaced by `interval_days` starting from `scheduled_at`.
- `sessions_count` is capped at 1–20 to prevent abuse.
- Sends a single `bulk_request_created` notification to the provider instead of one per session.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..d47b3cb 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
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
+      result = Requests::BulkCreateService.new(
+        client: client,
+        provider: provider,
+        params: bulk_request_params
+      ).call
+
+      if result[:success]
+        render json: result[:requests].map { |r| request_detail_json(r) }, status: :created
+      else
+        render_unprocessable(result[:errors])
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
@@ -109,6 +129,10 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def bulk_request_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency, :sessions_count, :interval_days)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request_clean/app/services/requests/bulk_create_service.rb b/affordance_request_clean/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..107a837
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,64 @@
+module Requests
+  class BulkCreateService
+    DEFAULT_SESSIONS_COUNT = 5
+    DEFAULT_INTERVAL_DAYS = 7
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      sessions_count = (@params[:sessions_count] || DEFAULT_SESSIONS_COUNT).to_i
+      interval_days = (@params[:interval_days] || DEFAULT_INTERVAL_DAYS).to_i
+
+      if sessions_count < 1 || sessions_count > 20
+        return { success: false, errors: ["sessions_count must be between 1 and 20"] }
+      end
+
+      requests = []
+
+      Request.transaction do
+        sessions_count.times do |i|
+          scheduled_at = Time.zone.parse(@params[:scheduled_at].to_s) + (i * interval_days).days
+
+          request = Request.new(
+            client: @client,
+            provider: @provider,
+            scheduled_at: scheduled_at,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB"
+          )
+          request.save!
+
+          Payment.create!(
+            request: request,
+            amount_cents: request.amount_cents,
+            currency: request.currency,
+            fee_cents: calculate_fee(request.amount_cents),
+            status: "pending"
+          )
+
+          requests << request
+        end
+      end
+
+      NotificationService.notify(@provider, :bulk_request_created, count: requests.size, client_id: @client.id)
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: [e.message] }
+    rescue ArgumentError
+      { success: false, errors: ["Invalid scheduled_at date"] }
+    end
+
+    private
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..d178bd6 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :bulk_create
+      end
       member do
         patch :confirm
         patch :start
```
