# Experiment: 04-bulk-booking
# App: request | Model: opus | Run: 1
# Branch: experiment/04-bulk-booking/request/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**New endpoint**: `POST /api/requests/bulk` — creates multiple recurring sessions in one API call.

**Parameters**:
- `provider_id`, `scheduled_at`, `duration_minutes`, `amount_cents`, `currency` — same as single create
- `count` — number of sessions (1-5, defaults to 5)
- `interval_days` — days between sessions (defaults to 7 for weekly)

**Key details**:
- All requests and their payments are created atomically in a single DB transaction — if any fails, all roll back
- Notifications are sent for each created request
- Client-only endpoint (providers get 403)
- 7 new tests covering: default 5-weekly creation, custom count/interval, count validation, auth, not-found, validation errors, and transaction rollback

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..7f5d0ff 100644
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
+        render_unprocessable(result[:errors])
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
index 0000000..bccb113
--- /dev/null
+++ b/affordance_request/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,67 @@
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
+      first_scheduled_at = Time.zone.parse(@params[:scheduled_at].to_s)
+      return { success: false, errors: ["scheduled_at is required"] } unless first_scheduled_at
+
+      count = (@params[:count] || MAX_SESSIONS).to_i
+      return { success: false, errors: ["count must be between 1 and #{MAX_SESSIONS}"] } unless count.between?(1, MAX_SESSIONS)
+
+      interval_days = (@params[:interval_days] || 7).to_i
+      return { success: false, errors: ["interval_days must be positive"] } unless interval_days > 0
+
+      requests = []
+
+      Request.transaction do
+        count.times do |i|
+          scheduled_at = first_scheduled_at + (i * interval_days).days
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
+      requests.each do |request|
+        NotificationService.notify(@provider, :request_created, request_id: request.id)
+      end
+
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors.full_messages }
+    rescue ArgumentError
+      { success: false, errors: ["scheduled_at is invalid"] }
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
index 772331d..e329e6d 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -224,4 +224,72 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/requests/bulk" do
+    let(:bulk_params) do
+      {
+        provider_id: provider.id,
+        scheduled_at: 3.days.from_now.iso8601,
+        duration_minutes: 120,
+        amount_cents: 350_000,
+        currency: "RUB"
+      }
+    end
+
+    it "creates 5 weekly requests by default" do
+      expect {
+        post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      }.to change(Request, :count).by(5).and change(Payment, :count).by(5)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+
+      scheduled_dates = body.map { |r| Time.zone.parse(r["scheduled_at"]) }
+      (1...scheduled_dates.length).each do |i|
+        expect(scheduled_dates[i] - scheduled_dates[i - 1]).to be_within(1.second).of(7.days)
+      end
+    end
+
+    it "accepts custom count and interval_days" do
+      expect {
+        post "/api/requests/bulk", params: bulk_params.merge(count: 3, interval_days: 14), headers: auth_headers(client)
+      }.to change(Request, :count).by(3)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(3)
+
+      scheduled_dates = body.map { |r| Time.zone.parse(r["scheduled_at"]) }
+      expect(scheduled_dates[1] - scheduled_dates[0]).to be_within(1.second).of(14.days)
+    end
+
+    it "rejects count greater than 5" do
+      post "/api/requests/bulk", params: bulk_params.merge(count: 6), headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
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
+    it "returns validation errors for missing fields" do
+      post "/api/requests/bulk", params: { provider_id: provider.id, scheduled_at: 3.days.from_now.iso8601 }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "rolls back all requests on validation failure" do
+      expect {
+        post "/api/requests/bulk", params: bulk_params.merge(amount_cents: nil), headers: auth_headers(client)
+      }.not_to change(Request, :count)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
```
