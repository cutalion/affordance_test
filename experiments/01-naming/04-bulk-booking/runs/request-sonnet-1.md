# Experiment: 04-bulk-booking
# App: request | Model: sonnet | Run: 1
# Branch: experiment/04-bulk-booking/request/sonnet/run-1

---

## Claude Output

Done. Here's what was implemented:

**`POST /api/requests/bulk`** — client-only endpoint

| Param | Default | Description |
|---|---|---|
| `provider_id` | required | Target provider |
| `scheduled_at` | required | First session time |
| `count` | 5 | Number of sessions (2–20) |
| `interval_days` | 7 | Days between sessions (1–365) |
| + standard request fields | | `duration_minutes`, `amount_cents`, etc. |

- Returns an array of all created request objects (`:created` status)
- Single DB transaction — all sessions created or none
- Each session gets its own `Payment` record
- Notifies the provider once for the whole batch

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..2128725 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -34,6 +34,26 @@ def create
       end
     end
 
+    def create_bulk
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
index 0000000..a54de44
--- /dev/null
+++ b/affordance_request/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,55 @@
+module Requests
+  class BulkCreateService
+    DEFAULT_COUNT = 5
+    DEFAULT_INTERVAL_DAYS = 7
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+      @count = (params[:count] || DEFAULT_COUNT).to_i.clamp(2, 20)
+      @interval_days = (params[:interval_days] || DEFAULT_INTERVAL_DAYS).to_i.clamp(1, 365)
+    end
+
+    def call
+      base_time = begin
+        Time.parse(@params[:scheduled_at].to_s)
+      rescue ArgumentError, TypeError
+        nil
+      end
+      requests = []
+
+      Request.transaction do
+        @count.times do |i|
+          scheduled_at = base_time ? base_time + (i * @interval_days).days : nil
+          session_params = @params.merge(scheduled_at: scheduled_at)
+
+          request = Request.new(
+            client: @client,
+            provider: @provider,
+            scheduled_at: session_params[:scheduled_at],
+            duration_minutes: session_params[:duration_minutes],
+            location: session_params[:location],
+            notes: session_params[:notes],
+            amount_cents: session_params[:amount_cents],
+            currency: session_params[:currency] || "RUB"
+          )
+          request.save!
+          Payment.create!(
+            request: request,
+            amount_cents: request.amount_cents,
+            currency: request.currency,
+            fee_cents: (request.amount_cents * 0.1).to_i,
+            status: "pending"
+          )
+          requests << request
+        end
+      end
+
+      NotificationService.notify(@provider, :bulk_requests_created, count: requests.size, first_request_id: requests.first.id)
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..3528c35 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -13,6 +13,7 @@
     resources :requests, only: [:index, :show, :create] do
       collection do
         post :direct, action: :create_direct
+        post :bulk, action: :create_bulk
       end
       member do
         patch :accept
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..adebb79 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -122,6 +122,71 @@
     end
   end
 
+  describe "POST /api/requests/bulk" do
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
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      body.each { |r| expect(r["state"]).to eq("created") }
+    end
+
+    it "schedules sessions 7 days apart by default" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      first = Time.parse(body[0]["scheduled_at"])
+      second = Time.parse(body[1]["scheduled_at"])
+      expect((second - first).to_i).to eq(7.days.to_i)
+    end
+
+    it "respects custom count and interval_days" do
+      post "/api/requests/bulk", params: bulk_params.merge(count: 3, interval_days: 14), headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(3)
+      first = Time.parse(body[0]["scheduled_at"])
+      third = Time.parse(body[2]["scheduled_at"])
+      expect((third - first).to_i).to eq(28.days.to_i)
+    end
+
+    it "creates a payment for each session" do
+      expect {
+        post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      }.to change(Payment, :count).by(5)
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
+    it "returns 401 without auth" do
+      post "/api/requests/bulk", params: bulk_params
+      expect(response).to have_http_status(:unauthorized)
+    end
+
+    it "returns validation errors and creates no requests on failure" do
+      expect {
+        post "/api/requests/bulk", params: { provider_id: provider.id }, headers: auth_headers(client)
+      }.not_to change(Request, :count)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/requests/:id/accept" do
     let(:req) { create(:request, client: client, provider: provider) }
 
```
