# Experiment: 02-rebook-feature
# App: request_clean | Model: sonnet | Run: 2
# Branch: experiment/02-rebook-feature/request_clean/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**`POST /api/requests/:id/rebook`** — Client-only endpoint.

- **`app/services/requests/rebook_service.rb`** — Validates the client owns the original request, then delegates to `CreateService` with the original's `provider`, `location`, `duration_minutes`, `amount_cents`, and `currency`. The client supplies a new `scheduled_at`; `notes` is optional (falls back to the original's notes).
- **Route**: `post :rebook` added as a member action on `resources :requests`.
- **Controller**: `rebook` action follows the same pattern as `create` — calls the service, returns 201 with the new request detail on success, 422 on error.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..4555bc2 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -34,6 +34,24 @@ def create
       end
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      result = Requests::RebookService.new(
+        request: @request,
+        client: client,
+        params: params.permit(:scheduled_at, :notes)
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      else
+        error = result[:errors]&.full_messages || [result[:error]]
+        render_unprocessable(error)
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
diff --git a/affordance_request_clean/app/services/requests/rebook_service.rb b/affordance_request_clean/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..4b17f39
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/rebook_service.rb
@@ -0,0 +1,30 @@
+module Requests
+  class RebookService
+    def initialize(request:, client:, params:)
+      @original = request
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @original.client == @client
+        return { success: false, error: "Not authorized" }
+      end
+
+      new_params = {
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @original.duration_minutes,
+        location: @original.location,
+        notes: @params[:notes].presence || @original.notes,
+        amount_cents: @original.amount_cents,
+        currency: @original.currency
+      }
+
+      CreateService.new(
+        client: @client,
+        provider: @original.provider,
+        params: new_params
+      ).call
+    end
+  end
+end
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..564cfee 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -17,6 +17,7 @@
         patch :complete
         patch :cancel
         patch :reject
+        post :rebook
       end
       resources :reviews, only: [:index, :create]
     end
```
