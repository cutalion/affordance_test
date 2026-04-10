# Experiment: 04-bulk-booking
# App: request | Model: sonnet | Run: 2
# Branch: experiment/04-bulk-booking/request/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**`POST /api/requests/bulk`** — client-only endpoint that creates 5 weekly sessions in a single API call.

**Files changed:**
- `app/services/requests/bulk_create_service.rb` — wraps all 5 request+payment creates in a single transaction; sessions spaced 7 days apart; notifies provider for each
- `config/routes.rb` — added `post :bulk, action: :create_bulk` under the requests collection
- `app/controllers/api/requests_controller.rb` — added `create_bulk` action returning an array of 5 request objects
- `spec/services/requests/bulk_create_service_spec.rb` — service unit tests
- `spec/requests/api/requests_spec.rb` — integration tests for the new endpoint

All 305 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..bff59e3 100644
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
     def create_direct
       provider = current_provider!
       return if performed?
diff --git a/affordance_request/app/services/requests/bulk_create_service.rb b/affordance_request/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..eb0a596
--- /dev/null
+++ b/affordance_request/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,64 @@
+module Requests
+  class BulkCreateService
+    SESSION_COUNT = 5
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
+      base = base_scheduled_at
+
+      Request.transaction do
+        SESSION_COUNT.times do |i|
+          scheduled_at = base ? base + (i * INTERVAL_DAYS).days : nil
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
+      return nil if @params[:scheduled_at].blank?
+      @base_scheduled_at ||= Time.zone.parse(@params[:scheduled_at].to_s)
+    end
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
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
index 772331d..b505416 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -93,6 +93,55 @@
     end
   end
 
+  describe "POST /api/requests/bulk" do
+    let(:bulk_params) do
+      {
+        provider_id: provider.id,
+        scheduled_at: 3.days.from_now.iso8601,
+        duration_minutes: 60,
+        amount_cents: 100_000,
+        currency: "RUB"
+      }
+    end
+
+    it "creates 5 weekly sessions for a client" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      body.each { |r| expect(r["state"]).to eq("created") }
+    end
+
+    it "spaces sessions one week apart" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body.map { |r| Time.zone.parse(r["scheduled_at"]) }
+      times.each_cons(2) do |a, b|
+        expect(b - a).to be_within(1).of(7.days)
+      end
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
+      post "/api/requests/bulk", params: { provider_id: provider.id }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 401 without auth" do
+      post "/api/requests/bulk", params: bulk_params
+      expect(response).to have_http_status(:unauthorized)
+    end
+  end
+
   describe "POST /api/requests/direct" do
     let(:direct_params) do
       {
diff --git a/affordance_request/spec/services/requests/bulk_create_service_spec.rb b/affordance_request/spec/services/requests/bulk_create_service_spec.rb
new file mode 100644
index 0000000..099ac1a
--- /dev/null
+++ b/affordance_request/spec/services/requests/bulk_create_service_spec.rb
@@ -0,0 +1,85 @@
+require "rails_helper"
+
+RSpec.describe Requests::BulkCreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:valid_params) do
+    {
+      scheduled_at: 3.days.from_now,
+      duration_minutes: 60,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 100_000,
+      currency: "RUB"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }
+
+  describe "#call" do
+    context "with valid params" do
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+        expect(result[:success]).to be true
+        expect(result[:requests].length).to eq(5)
+      end
+
+      it "creates requests in weekly intervals" do
+        base_time = valid_params[:scheduled_at]
+        requests = result[:requests]
+
+        requests.each_with_index do |req, i|
+          expected_time = base_time + i.weeks
+          expect(req.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "creates all requests in created state" do
+        result[:requests].each do |req|
+          expect(req.state).to eq("created")
+        end
+      end
+
+      it "creates a pending payment for each request" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:requests].each do |req|
+          expect(req.payment.status).to eq("pending")
+          expect(req.payment.fee_cents).to eq(10_000)
+          expect(req.payment.amount_cents).to eq(100_000)
+        end
+      end
+
+      it "notifies the provider for each request" do
+        result
+        request_ids = result[:requests].map(&:id)
+        request_ids.each do |id|
+          expect(read_notification_log).to include("request_id=#{id}")
+        end
+      end
+
+      it "sets the same client and provider on all requests" do
+        result[:requests].each do |req|
+          expect(req.client).to eq(client)
+          expect(req.provider).to eq(provider)
+        end
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
+
+      it "returns failure with errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "creates no requests" do
+        expect { result }.not_to change(Request, :count)
+      end
+
+      it "creates no payments" do
+        expect { result }.not_to change(Payment, :count)
+      end
+    end
+  end
+end
```
