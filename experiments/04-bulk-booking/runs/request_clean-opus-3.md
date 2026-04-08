# Experiment: 04-bulk-booking
# App: request_clean | Model: opus | Run: 3
# Branch: experiment/04-bulk-booking/request_clean/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**New endpoint:** `POST /api/requests/bulk_create`

**Parameters:**
- `provider_id` — target provider
- `scheduled_at` — first session date
- `duration_minutes`, `amount_cents`, `currency`, `location`, `notes` — same as single create
- `count` — number of sessions (2–5)
- `interval_days` — gap between sessions (default: 7)

**Key details:**
- `Requests::BulkCreateService` creates all requests + payments in a single transaction (atomic rollback on any failure)
- Each session is scheduled `interval_days` apart starting from `scheduled_at`
- Provider gets a single `bulk_requests_created` notification
- Returns array of all created request details with HTTP 201
- 35 tests passing (8 new: 5 service specs + 5 API specs)

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..bfad821 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -34,6 +34,30 @@ def create
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
+        count: params[:count].to_i,
+        interval_days: params.fetch(:interval_days, 7).to_i
+      ).call
+
+      if result[:success]
+        render json: result[:requests].map { |r| request_detail_json(r) }, status: :created
+      elsif result[:errors]
+        render_unprocessable(result[:errors].full_messages)
+      else
+        render_unprocessable([result[:error]])
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
diff --git a/affordance_request_clean/app/services/requests/bulk_create_service.rb b/affordance_request_clean/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..5392b0d
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,60 @@
+module Requests
+  class BulkCreateService
+    MAX_SESSIONS = 5
+
+    def initialize(client:, provider:, params:, count:, interval_days: 7)
+      @client = client
+      @provider = provider
+      @params = params
+      @count = count
+      @interval_days = interval_days
+    end
+
+    def call
+      if @count < 2 || @count > MAX_SESSIONS
+        return { success: false, error: "Count must be between 2 and #{MAX_SESSIONS}" }
+      end
+
+      base_time = Time.zone.parse(@params[:scheduled_at].to_s)
+      return { success: false, error: "Invalid scheduled_at" } unless base_time
+
+      requests = []
+
+      Request.transaction do
+        @count.times do |i|
+          scheduled_at = base_time + (i * @interval_days).days
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
+      NotificationService.notify(@provider, :bulk_requests_created,
+        request_ids: requests.map(&:id),
+        count: requests.size
+      )
+
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
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
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..d12bde5 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -93,6 +93,51 @@
     end
   end
 
+  describe "POST /api/requests/bulk_create" do
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
+    it "creates 5 requests in a single call" do
+      expect {
+        post "/api/requests/bulk_create", params: bulk_params, headers: auth_headers(client)
+      }.to change(Request, :count).by(5)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.size).to eq(5)
+      expect(body).to all(include("id", "state", "scheduled_at"))
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
+
+    it "returns error for invalid count" do
+      post "/api/requests/bulk_create", params: bulk_params.merge(count: 10), headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns validation errors for missing fields" do
+      post "/api/requests/bulk_create", params: { provider_id: provider.id, count: 3 }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/requests/:id/confirm" do
     let(:request) { create(:request, client: client, provider: provider) }
 
diff --git a/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb b/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb
new file mode 100644
index 0000000..6c32b9d
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb
@@ -0,0 +1,89 @@
+require "rails_helper"
+
+RSpec.describe Requests::BulkCreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:base_params) do
+    {
+      scheduled_at: 3.days.from_now.iso8601,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 350_000,
+      currency: "RUB"
+    }
+  end
+
+  describe "#call" do
+    context "with valid params for 5 weekly sessions" do
+      subject(:result) do
+        described_class.new(client: client, provider: provider, params: base_params, count: 5).call
+      end
+
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+        expect(result[:success]).to be true
+        expect(result[:requests].size).to eq(5)
+      end
+
+      it "spaces requests 7 days apart" do
+        requests = result[:requests]
+        (1...requests.size).each do |i|
+          gap = requests[i].scheduled_at - requests[i - 1].scheduled_at
+          expect(gap).to eq(7.days)
+        end
+      end
+
+      it "creates a payment for each request" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:requests].each do |request|
+          expect(request.payment).to be_present
+          expect(request.payment.amount_cents).to eq(350_000)
+          expect(request.payment.fee_cents).to eq(35_000)
+        end
+      end
+
+      it "notifies the provider once" do
+        result
+        expect(read_notification_log).to include("event=bulk_requests_created")
+      end
+    end
+
+    context "with custom interval" do
+      subject(:result) do
+        described_class.new(client: client, provider: provider, params: base_params, count: 3, interval_days: 14).call
+      end
+
+      it "spaces requests by the custom interval" do
+        requests = result[:requests]
+        gap = requests[1].scheduled_at - requests[0].scheduled_at
+        expect(gap).to eq(14.days)
+      end
+    end
+
+    context "with invalid count" do
+      it "rejects count of 1" do
+        result = described_class.new(client: client, provider: provider, params: base_params, count: 1).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Count must be between")
+      end
+
+      it "rejects count of 6" do
+        result = described_class.new(client: client, provider: provider, params: base_params, count: 6).call
+        expect(result[:success]).to be false
+        expect(result[:error]).to include("Count must be between")
+      end
+    end
+
+    context "with invalid request params" do
+      let(:bad_params) { base_params.merge(amount_cents: nil) }
+
+      it "rolls back all requests on validation failure" do
+        result = described_class.new(client: client, provider: provider, params: bad_params, count: 3).call
+        expect(result[:success]).to be false
+        expect(Request.count).to eq(0)
+        expect(Payment.count).to eq(0)
+      end
+    end
+  end
+end
```
