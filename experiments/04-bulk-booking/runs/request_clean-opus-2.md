# Experiment: 04-bulk-booking
# App: request_clean | Model: opus | Run: 2
# Branch: experiment/04-bulk-booking/request_clean/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**New endpoint:** `POST /api/requests/bulk`

**How it works:**
- Client sends the first session's details plus `recurrence_count` (defaults to 5, max 20)
- Creates N requests scheduled 1 week apart, each with its own payment, in a single DB transaction
- Sends one notification to the provider for the whole batch
- Returns all created requests as a JSON array

**Files changed:**
- `app/services/requests/bulk_create_service.rb` — new service handling bulk creation
- `app/controllers/api/requests_controller.rb` — added `bulk_create` action
- `config/routes.rb` — added `POST /api/requests/bulk` route
- `spec/services/requests/bulk_create_service_spec.rb` — 9 service tests
- `spec/requests/api/requests_spec.rb` — 5 API integration tests

All 280 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..b1cfb3f 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
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
+        params: bulk_request_params
+      ).call
+
+      if result[:success]
+        render json: result[:requests].map { |r| request_detail_json(r) }, status: :created
+      elsif result[:errors]
+        render_unprocessable(result[:errors].full_messages)
+      else
+        render json: { error: result[:error] }, status: :unprocessable_entity
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
@@ -109,6 +131,10 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def bulk_request_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency, :recurrence_count)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request_clean/app/services/requests/bulk_create_service.rb b/affordance_request_clean/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..e02ce17
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,59 @@
+module Requests
+  class BulkCreateService
+    DEFAULT_COUNT = 5
+    MAX_COUNT = 20
+    RECURRENCE_INTERVAL = 1.week
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+      @count = [(params[:recurrence_count] || DEFAULT_COUNT).to_i, MAX_COUNT].min
+    end
+
+    def call
+      return { success: false, error: "Count must be at least 2" } if @count < 2
+
+      base_time = @params[:scheduled_at].present? ? Time.zone.parse(@params[:scheduled_at].to_s) : nil
+      requests = []
+
+      Request.transaction do
+        @count.times do |i|
+          scheduled_at = base_time ? base_time + (i * RECURRENCE_INTERVAL) : nil
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
+  end
+end
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..bf001e7 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :bulk, action: :bulk_create
+      end
       member do
         patch :confirm
         patch :start
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..067b558 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -93,6 +93,47 @@
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
+        recurrence_count: 5
+      }
+    end
+
+    it "creates 5 weekly recurring requests" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      expect(body.map { |r| r["state"] }.uniq).to eq(["pending"])
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
+      post "/api/requests/bulk", params: { provider_id: provider.id, recurrence_count: 5 }, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns error when recurrence_count is less than 2" do
+      post "/api/requests/bulk", params: bulk_params.merge(recurrence_count: 1), headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
+
   describe "PATCH /api/requests/:id/confirm" do
     let(:request) { create(:request, client: client, provider: provider) }
 
diff --git a/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb b/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb
new file mode 100644
index 0000000..4bb03a7
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb
@@ -0,0 +1,108 @@
+require "rails_helper"
+
+RSpec.describe Requests::BulkCreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:valid_params) do
+    {
+      scheduled_at: 3.days.from_now.iso8601,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 350_000,
+      currency: "RUB",
+      recurrence_count: 5
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
+      it "schedules requests one week apart" do
+        requests = result[:requests]
+        scheduled_times = requests.map(&:scheduled_at)
+
+        (1...scheduled_times.length).each do |i|
+          diff = scheduled_times[i] - scheduled_times[i - 1]
+          expect(diff).to be_within(1.second).of(1.week)
+        end
+      end
+
+      it "creates a payment for each request" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:requests].each do |request|
+          expect(request.payment).to be_present
+          expect(request.payment.status).to eq("pending")
+          expect(request.payment.fee_cents).to eq(35_000)
+        end
+      end
+
+      it "notifies the provider once" do
+        result
+        expect(read_notification_log).to include("event=bulk_request_created")
+      end
+
+      it "sets all requests to pending state" do
+        result[:requests].each do |request|
+          expect(request.state).to eq("pending")
+        end
+      end
+    end
+
+    context "with custom recurrence count" do
+      before { valid_params[:recurrence_count] = 3 }
+
+      it "creates the specified number of requests" do
+        expect { result }.to change(Request, :count).by(3)
+      end
+    end
+
+    context "without recurrence_count" do
+      before { valid_params.delete(:recurrence_count) }
+
+      it "defaults to 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+    end
+
+    context "with count less than 2" do
+      before { valid_params[:recurrence_count] = 1 }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Count must be at least 2")
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil, recurrence_count: 5 } }
+
+      it "returns errors and creates no records" do
+        expect { result }.not_to change(Request, :count)
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+    end
+
+    context "rolls back all on partial failure" do
+      it "creates no requests if any request is invalid" do
+        allow_any_instance_of(Request).to receive(:save!).and_call_original
+        call_count = 0
+        allow(Payment).to receive(:create!).and_wrap_original do |method, **args|
+          call_count += 1
+          raise ActiveRecord::RecordInvalid.new(Payment.new) if call_count == 3
+          method.call(**args)
+        end
+
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+  end
+end
```
