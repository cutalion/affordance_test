# Experiment: 04-bulk-booking
# App: request | Model: opus | Run: 2
# Branch: experiment/04-bulk-booking/request/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**New endpoint:** `POST /api/requests/bulk`

**Parameters:**
- `provider_id` — target provider
- `scheduled_at` — first session date/time
- `duration_minutes`, `amount_cents`, `currency`, `location`, `notes` — same as single booking
- `count` — number of sessions (default: 5, max: 10)
- `interval_days` — days between sessions (default: 7)

**Key details:**
- All requests and payments are created atomically in a single transaction — if any fails, all roll back
- Each request gets its own payment with 10% fee
- Provider is notified once with all request IDs
- Only clients can use this endpoint (providers get 403)

**Files changed:**
- `app/services/requests/bulk_create_service.rb` — new service
- `app/controllers/api/requests_controller.rb` — new `bulk_create` action
- `config/routes.rb` — new route
- `spec/services/requests/bulk_create_service_spec.rb` — 8 unit tests
- `spec/requests/api/requests_spec.rb` — 5 integration tests

All 304 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..2b57318 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -34,6 +34,28 @@ def create
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
+        params: request_params,
+        count: params[:count] || 5,
+        interval_days: params[:interval_days] || 7
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
diff --git a/affordance_request/app/services/requests/bulk_create_service.rb b/affordance_request/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..00dae28
--- /dev/null
+++ b/affordance_request/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,63 @@
+module Requests
+  class BulkCreateService
+    MAX_SESSIONS = 10
+
+    def initialize(client:, provider:, params:, count:, interval_days:)
+      @client = client
+      @provider = provider
+      @params = params
+      @count = count.to_i
+      @interval_days = interval_days.to_i
+    end
+
+    def call
+      return error_result("Count must be between 2 and #{MAX_SESSIONS}") unless @count.between?(2, MAX_SESSIONS)
+      return error_result("Interval days must be positive") unless @interval_days > 0
+
+      base_time = @params[:scheduled_at]
+      return error_result("Scheduled at is required") if base_time.blank?
+
+      requests = []
+
+      Request.transaction do
+        @count.times do |i|
+          scheduled_at = Time.parse(base_time.to_s) + i * @interval_days.days
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
+            fee_cents: (request.amount_cents * 0.1).to_i,
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
index 772331d..8c9233c 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -122,6 +122,56 @@
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
+    it "creates multiple requests in a single call" do
+      expect {
+        post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      }.to change(Request, :count).by(5)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      expect(body.map { |r| r["state"] }.uniq).to eq(["created"])
+    end
+
+    it "defaults to 5 sessions with 7-day interval" do
+      params_without_defaults = bulk_params.except(:count, :interval_days)
+
+      expect {
+        post "/api/requests/bulk", params: params_without_defaults, headers: auth_headers(client)
+      }.to change(Request, :count).by(5)
+
+      expect(response).to have_http_status(:created)
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
+    it "returns validation errors for invalid params" do
+      post "/api/requests/bulk", params: bulk_params.merge(count: 0), headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/requests/:id/accept" do
     let(:req) { create(:request, client: client, provider: provider) }
 
diff --git a/affordance_request/spec/services/requests/bulk_create_service_spec.rb b/affordance_request/spec/services/requests/bulk_create_service_spec.rb
new file mode 100644
index 0000000..4ffee4f
--- /dev/null
+++ b/affordance_request/spec/services/requests/bulk_create_service_spec.rb
@@ -0,0 +1,107 @@
+require "rails_helper"
+
+RSpec.describe Requests::BulkCreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:base_time) { 3.days.from_now }
+  let(:valid_params) do
+    {
+      scheduled_at: base_time.iso8601,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 350_000,
+      currency: "RUB"
+    }
+  end
+
+  subject(:result) do
+    described_class.new(
+      client: client,
+      provider: provider,
+      params: valid_params,
+      count: count,
+      interval_days: interval_days
+    ).call
+  end
+
+  let(:count) { 5 }
+  let(:interval_days) { 7 }
+
+  describe "#call" do
+    context "with valid params" do
+      it "creates the specified number of requests" do
+        expect { result }.to change(Request, :count).by(5)
+        expect(result[:success]).to be true
+        expect(result[:requests].length).to eq(5)
+      end
+
+      it "schedules requests at weekly intervals" do
+        requests = result[:requests]
+        requests.each_with_index do |req, i|
+          expected_time = Time.parse(base_time.iso8601) + i * 7.days
+          expect(req.scheduled_at).to eq(expected_time)
+        end
+      end
+
+      it "creates a payment for each request" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:requests].each do |req|
+          expect(req.payment).to be_present
+          expect(req.payment.status).to eq("pending")
+          expect(req.payment.fee_cents).to eq(35_000)
+        end
+      end
+
+      it "notifies the provider once" do
+        result
+        expect(read_notification_log).to include("event=bulk_request_created")
+      end
+    end
+
+    context "with custom interval" do
+      let(:interval_days) { 14 }
+
+      it "spaces requests by the given interval" do
+        requests = result[:requests]
+        expect(requests[1].scheduled_at - requests[0].scheduled_at).to eq(14.days)
+      end
+    end
+
+    context "with invalid count" do
+      let(:count) { 0 }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors].full_messages).to include(/Count must be between/)
+      end
+    end
+
+    context "with count exceeding maximum" do
+      let(:count) { 11 }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors].full_messages).to include(/Count must be between/)
+      end
+    end
+
+    context "with invalid interval" do
+      let(:interval_days) { 0 }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors].full_messages).to include(/Interval days must be positive/)
+      end
+    end
+
+    context "with invalid request params" do
+      let(:valid_params) { { scheduled_at: base_time.iso8601, duration_minutes: nil, amount_cents: nil, currency: nil } }
+
+      it "rolls back all requests on validation failure" do
+        expect { result }.not_to change(Request, :count)
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
