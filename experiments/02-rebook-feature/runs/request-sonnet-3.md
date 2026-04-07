# Experiment: 02-rebook-feature
# App: request | Model: sonnet | Run: 3
# Branch: experiment/02-rebook-feature/request/sonnet/run-3

---

## Claude Output

The rebook feature is implemented and committed. Here's a summary of what was added:

### Changes

**`app/services/requests/rebook_service.rb`** (new)
- Verifies the requesting client owns the original booking
- Creates a new `Request` copying `provider`, `location`, and `duration_minutes` from the original
- Requires a new `scheduled_at`; optionally accepts `notes` and `amount_cents` (falls back to the original amount)
- Creates the associated pending `Payment` and notifies the provider

**`app/controllers/api/requests_controller.rb`**
- Added `rebook` action that authenticates the client, delegates to `RebookService`, and returns the new request as JSON (201 Created)
- Added `rebook_params` to permit `scheduled_at`, `notes`, and `amount_cents`

**`config/routes.rb`**
- Added `POST /api/requests/:id/rebook` route

All 290 existing tests continue to pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..972f96c 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -102,6 +102,25 @@ def cancel
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      result = Requests::RebookService.new(
+        original_request: @the_request,
+        client: client,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      elsif result[:error] == "Forbidden"
+        render_forbidden
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def reject
       provider = current_provider!
       return if performed?
@@ -137,6 +156,10 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :notes, :amount_cents)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request/app/services/requests/rebook_service.rb b/affordance_request/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..e09e641
--- /dev/null
+++ b/affordance_request/app/services/requests/rebook_service.rb
@@ -0,0 +1,48 @@
+module Requests
+  class RebookService
+    def initialize(original_request:, client:, params:)
+      @original_request = original_request
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @original_request.client == @client
+        return { success: false, error: "Forbidden" }
+      end
+
+      request = Request.new(
+        client: @client,
+        provider: @original_request.provider,
+        location: @original_request.location,
+        duration_minutes: @original_request.duration_minutes,
+        scheduled_at: @params[:scheduled_at],
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents] || @original_request.amount_cents,
+        currency: @original_request.currency
+      )
+
+      Request.transaction do
+        request.save!
+        Payment.create!(
+          request: request,
+          amount_cents: request.amount_cents,
+          currency: request.currency,
+          fee_cents: calculate_fee(request.amount_cents),
+          status: "pending"
+        )
+      end
+
+      NotificationService.notify(request.provider, :request_created, request_id: request.id)
+      { success: true, request: request }
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
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..4a162af 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -21,6 +21,7 @@
         patch :fulfill
         patch :cancel
         patch :reject
+        post :rebook
       end
       resources :reviews, only: [:index, :create]
     end
```
