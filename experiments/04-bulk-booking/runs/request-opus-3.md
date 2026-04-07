# Experiment: 04-bulk-booking
# App: request | Model: opus | Run: 3
# Branch: experiment/04-bulk-booking/request/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**Endpoint:** `POST /api/requests/bulk` (client-only)

**Parameters:**
- `provider_id` — target provider
- `scheduled_at` — first session time
- `duration_minutes`, `amount_cents`, `currency`, `location`, `notes` — same as single create
- `count` — number of sessions (2-5, default 5)
- `interval_days` — days between sessions (1-30, default 7)

**Key behaviors:**
- All sessions created atomically in a single DB transaction — if any fails, all roll back
- Each session gets its own payment record with 10% fee (matching existing logic)
- Provider receives a single `bulk_request_created` notification with all request IDs
- Returns array of full request detail objects with 201 status

**Files changed:**
- `app/services/requests/bulk_create_service.rb` — new service
- `app/controllers/api/requests_controller.rb` — `bulk_create` action + params
- `config/routes.rb` — `post :bulk` route
- `spec/requests/api/requests_spec.rb` — 8 new tests (all passing)

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..0c92eb7 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
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
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def create_direct
       provider = current_provider!
       return if performed?
@@ -137,6 +157,10 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def bulk_request_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency, :count, :interval_days)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request/app/services/requests/bulk_create_service.rb b/affordance_request/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..edfec9e
--- /dev/null
+++ b/affordance_request/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,68 @@
+module Requests
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
+      return error_result("Count must be between 2 and #{MAX_SESSIONS}") unless count.between?(2, MAX_SESSIONS)
+
+      interval_days = (@params[:interval_days] || 7).to_i
+      return error_result("Interval must be between 1 and 30 days") unless interval_days.between?(1, 30)
+
+      base_time = @params[:scheduled_at]
+      return error_result("scheduled_at is required") if base_time.blank?
+
+      requests = []
+
+      Request.transaction do
+        count.times do |i|
+          scheduled_at = Time.parse(base_time.to_s) + (i * interval_days).days
+
+          request = Request.create!(
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
+      NotificationService.notify(@provider, :bulk_request_created, request_ids: requests.map(&:id))
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+
+    def error_result(message)
+      errors = ActiveModel::Errors.new(Request.new)
+      errors.add(:base, message)
+      { success: false, errors: errors }
+    end
+  end
+end
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..f7cd41b 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -13,6 +13,7 @@
     resources :requests, only: [:index, :show, :create] do
       collection do
         post :direct, action: :create_direct
+        post :bulk, action: :bulk_create
       end
       member do
         patch :accept
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..54b2adc 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -122,6 +122,74 @@
     end
   end
 
+  describe "POST /api/requests/bulk" do
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
+    it "creates multiple requests with weekly recurrence" do
+      expect {
+        post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      }.to change(Request, :count).by(5).and change(Payment, :count).by(5)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      expect(body.map { |r| r["state"] }.uniq).to eq(["created"])
+    end
+
+    it "spaces sessions by interval_days" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body.map { |r| Time.parse(r["scheduled_at"]) }
+      times.each_cons(2) do |a, b|
+        expect((b - a).to_i).to eq(7.days.to_i)
+      end
+    end
+
+    it "defaults to 5 sessions with 7-day intervals" do
+      post "/api/requests/bulk", params: bulk_params.except(:count, :interval_days), headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for non-existent provider" do
+      post "/api/requests/bulk", params: bulk_params.merge(provider_id: 99999), headers: auth_headers(client)
+      expect(response).to have_http_status(:not_found)
+    end
+
+    it "returns error when count exceeds maximum" do
+      post "/api/requests/bulk", params: bulk_params.merge(count: 10), headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns validation errors for missing fields" do
+      post "/api/requests/bulk", params: { provider_id: provider.id, count: 3 }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "rolls back all requests if any fails" do
+      expect {
+        post "/api/requests/bulk", params: bulk_params.merge(amount_cents: nil), headers: auth_headers(client)
+      }.not_to change(Request, :count)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/requests/:id/accept" do
     let(:req) { create(:request, client: client, provider: provider) }
 
```
