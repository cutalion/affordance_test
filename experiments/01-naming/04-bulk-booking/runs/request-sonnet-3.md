# Experiment: 04-bulk-booking
# App: request | Model: sonnet | Run: 3
# Branch: experiment/04-bulk-booking/request/sonnet/run-3

---

## Claude Output

Done. Here's what was added:

- **`POST /api/requests/bulk`** — client-only endpoint that creates 5 weekly sessions in one call
- **`Requests::CreateBulkService`** — wraps all 5 request + payment creations in a single transaction; rolls back all if any fails; sends one provider notification
- **Specs** — service spec (5 sessions, 7-day spacing, payments, rollback on invalid params) and request spec (happy path, auth, validation)

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..de52fd9 100644
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
+      result = Requests::CreateBulkService.new(
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
diff --git a/affordance_request/app/services/requests/create_bulk_service.rb b/affordance_request/app/services/requests/create_bulk_service.rb
new file mode 100644
index 0000000..6b8d868
--- /dev/null
+++ b/affordance_request/app/services/requests/create_bulk_service.rb
@@ -0,0 +1,57 @@
+module Requests
+  class CreateBulkService
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
+        base_time = @params[:scheduled_at].present? ? Time.parse(@params[:scheduled_at].to_s) : nil
+
+        SESSIONS_COUNT.times do |i|
+          scheduled_at = base_time ? base_time + (i * INTERVAL_DAYS).days : nil
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
+      NotificationService.notify(@provider, :bulk_requests_created, count: SESSIONS_COUNT, first_request_id: requests.first.id)
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
index 772331d..5d25b5f 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -122,6 +122,55 @@
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
+    it "creates 5 weekly sessions for the client" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body.length).to eq(5)
+      expect(body.map { |r| r["state"] }).to all(eq("created"))
+    end
+
+    it "spaces sessions 7 days apart" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      body = JSON.parse(response.body)
+      times = body.map { |r| Time.parse(r["scheduled_at"]) }
+      times.each_cons(2) do |a, b|
+        expect((b - a).to_i).to be_within(1).of(7.days.to_i)
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
   describe "PATCH /api/requests/:id/accept" do
     let(:req) { create(:request, client: client, provider: provider) }
 
diff --git a/affordance_request/spec/services/requests/create_bulk_service_spec.rb b/affordance_request/spec/services/requests/create_bulk_service_spec.rb
new file mode 100644
index 0000000..07c9444
--- /dev/null
+++ b/affordance_request/spec/services/requests/create_bulk_service_spec.rb
@@ -0,0 +1,76 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateBulkService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:first_session_at) { 3.days.from_now }
+  let(:valid_params) do
+    {
+      scheduled_at: first_session_at,
+      duration_minutes: 60,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 200_000,
+      currency: "RUB"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }
+
+  describe "#call" do
+    context "with valid params" do
+      it "returns success" do
+        expect(result[:success]).to be true
+      end
+
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+
+      it "creates requests in created state" do
+        result[:requests].each do |req|
+          expect(req.state).to eq("created")
+        end
+      end
+
+      it "spaces sessions 7 days apart" do
+        requests = result[:requests]
+        requests.each_with_index do |req, i|
+          expected_time = first_session_at + (i * 7).days
+          expect(req.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "creates a payment for each session" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:requests].each do |req|
+          expect(req.payment).to be_present
+          expect(req.payment.status).to eq("pending")
+          expect(req.payment.fee_cents).to eq(20_000)
+        end
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=bulk_requests_created")
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "does not create any requests" do
+        expect { result }.not_to change(Request, :count)
+      end
+
+      it "does not create any payments" do
+        expect { result }.not_to change(Payment, :count)
+      end
+    end
+  end
+end
```
