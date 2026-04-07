# Experiment: 02-rebook-feature
# App: request | Model: sonnet | Run: 1
# Branch: experiment/02-rebook-feature/request/sonnet/run-1

---

## Claude Output

The rebook feature is implemented and committed. Here's a summary of what was added:

### Changes

**`app/services/requests/rebook_service.rb`** (new)
- Verifies the original request belongs to the requesting client
- Delegates to the existing `CreateService`, carrying over `provider`, `location`, `duration_minutes`, `amount_cents`, and `currency` from the original booking
- Accepts a new `scheduled_at` (required) and optional `notes` override

**`app/controllers/api/requests_controller.rb`**
- Added `rebook` action that requires the client to be authenticated and provide a `scheduled_at`
- Returns `201 Created` with the new request's full detail JSON

**`config/routes.rb`**
- Added `POST /api/requests/:id/rebook` as a member route

### Usage

```
POST /api/requests/:id/rebook
Authorization: <client token>

{
  "scheduled_at": "2026-05-01T10:00:00Z",
  "notes": "Same as before, please!"   # optional
}
```

The new booking inherits the same **provider**, **location**, and **duration** from the original. All 290 existing specs continue to pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..1ebda37 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -102,6 +102,27 @@ def cancel
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      if params[:scheduled_at].blank?
+        return render_unprocessable(["Scheduled at is required"])
+      end
+
+      result = Requests::RebookService.new(
+        original_request: @the_request,
+        client: client,
+        params: params.permit(:scheduled_at, :notes)
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      else
+        render_unprocessable(result[:errors]&.full_messages || [result[:error]])
+      end
+    end
+
     def reject
       provider = current_provider!
       return if performed?
diff --git a/affordance_request/app/services/requests/rebook_service.rb b/affordance_request/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..e80ffa3
--- /dev/null
+++ b/affordance_request/app/services/requests/rebook_service.rb
@@ -0,0 +1,34 @@
+module Requests
+  class RebookService
+    def initialize(original_request:, client:, params:)
+      @original_request = original_request
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @original_request.client_id == @client.id
+        return { success: false, error: "Request not found" }
+      end
+
+      CreateService.new(
+        client: @client,
+        provider: @original_request.provider,
+        params: merged_params
+      ).call
+    end
+
+    private
+
+    def merged_params
+      {
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @original_request.duration_minutes,
+        location: @original_request.location,
+        notes: @params[:notes],
+        amount_cents: @original_request.amount_cents,
+        currency: @original_request.currency
+      }
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
