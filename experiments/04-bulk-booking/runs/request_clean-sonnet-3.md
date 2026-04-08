# Experiment: 04-bulk-booking
# App: request_clean | Model: sonnet | Run: 3
# Branch: experiment/04-bulk-booking/request_clean/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**`POST /api/requests/bulk_create`** — creates 5 weekly sessions in one atomic transaction.

**Files changed:**
- `app/services/requests/bulk_create_service.rb` — new service, loops 5 times offsetting `scheduled_at` by 7 days each iteration; wraps all saves + payment creations in a single transaction
- `app/controllers/api/requests_controller.rb` — `bulk_create` action, same shape as `create`
- `config/routes.rb` — `post :bulk_create, on: :collection`
- `spec/requests/api/requests_spec.rb` — 6 new tests covering: creates 5 requests, weekly spacing, 5 payments, all-or-nothing failure, 403 for provider, 404 for missing provider

All 28 specs pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..6e2474f 100644
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
+        params: request_params
+      ).call
+
+      if result[:success]
+        render json: result[:requests].map { |r| request_detail_json(r) }, status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
diff --git a/affordance_request_clean/app/services/requests/bulk_create_service.rb b/affordance_request_clean/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..865e6a4
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,63 @@
+module Requests
+  class BulkCreateService
+    SESSIONS_COUNT = 5
+    INTERVAL_DAYS = 7
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      requests = []
+
+      Request.transaction do
+        SESSIONS_COUNT.times do |i|
+          scheduled_at = base_scheduled_at + (i * INTERVAL_DAYS).days
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
+
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
+      requests.each do |request|
+        NotificationService.notify(@provider, :request_created, request_id: request.id)
+      end
+
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def base_scheduled_at
+      @base_scheduled_at ||= Time.zone.parse(@params[:scheduled_at].to_s)
+    end
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..e24d875 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -11,6 +11,7 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      post :bulk_create, on: :collection
       member do
         patch :confirm
         patch :start
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..8d3be86 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -166,6 +166,59 @@
     end
   end
 
+  describe "POST /api/requests/bulk_create" do
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
+    it "creates 5 weekly requests for a client" do
+      post "/api/requests/bulk_create", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      body.each { |r| expect(r["state"]).to eq("pending") }
+    end
+
+    it "schedules requests one week apart" do
+      post "/api/requests/bulk_create", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body.map { |r| Time.zone.parse(r["scheduled_at"]) }
+      4.times do |i|
+        expect(times[i + 1] - times[i]).to eq(7.days)
+      end
+    end
+
+    it "creates a payment for each request" do
+      expect {
+        post "/api/requests/bulk_create", params: bulk_params, headers: auth_headers(client)
+      }.to change(Payment, :count).by(5)
+    end
+
+    it "creates all or nothing on failure" do
+      invalid_params = bulk_params.merge(duration_minutes: -1)
+      expect {
+        post "/api/requests/bulk_create", params: invalid_params, headers: auth_headers(client)
+      }.not_to change(Request, :count)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/bulk_create", params: bulk_params, headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for non-existent provider" do
+      post "/api/requests/bulk_create", params: bulk_params.merge(provider_id: 99999), headers: auth_headers(client)
+      expect(response).to have_http_status(:not_found)
+    end
+  end
+
   describe "PATCH /api/requests/:id/reject" do
     let(:request) { create(:request, :confirmed, client: client, provider: provider) }
 
```
