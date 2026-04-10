# Experiment: 04-bulk-booking
# App: request_clean | Model: opus | Run: 1
# Branch: experiment/04-bulk-booking/request_clean/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**Endpoint:** `POST /api/requests/bulk` (client-only)

**API contract:** Send `provider_id`, shared defaults (`duration_minutes`, `location`, `notes`, `amount_cents`, `currency`), and a `sessions` array of 5 objects each with `scheduled_at` (and optional per-session overrides).

**Implementation:**
- `Requests::BulkCreateService` — creates all 5 requests + payments in a single DB transaction; rolls back everything if any session is invalid; notifies the provider for each created request
- Route added before `resources :requests` to avoid route conflicts
- `bulk_create` action in `Api::RequestsController` with dedicated strong params

**Tests:** 9 new tests (4 service-level, 5 integration) — full suite passes (278 examples, 0 failures).

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..a68bfd4 100644
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
+        params: bulk_request_params
+      ).call
+
+      if result[:success]
+        render json: { requests: result[:requests].map { |r| request_detail_json(r) } }, status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def confirm
       provider = current_provider!
       return if performed?
@@ -109,6 +129,13 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def bulk_request_params
+      params.permit(
+        :duration_minutes, :location, :notes, :amount_cents, :currency,
+        sessions: [:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency]
+      )
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request_clean/app/services/requests/bulk_create_service.rb b/affordance_request_clean/app/services/requests/bulk_create_service.rb
new file mode 100644
index 0000000..4542333
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/bulk_create_service.rb
@@ -0,0 +1,66 @@
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
+      sessions = @params[:sessions]
+      return error_result("Sessions are required") if sessions.blank?
+      return error_result("Exactly #{MAX_SESSIONS} sessions are required") if sessions.length != MAX_SESSIONS
+
+      requests = []
+
+      Request.transaction do
+        sessions.each do |session_params|
+          request = Request.new(
+            client: @client,
+            provider: @provider,
+            scheduled_at: session_params[:scheduled_at],
+            duration_minutes: session_params[:duration_minutes] || @params[:duration_minutes],
+            location: session_params[:location] || @params[:location],
+            notes: session_params[:notes] || @params[:notes],
+            amount_cents: session_params[:amount_cents] || @params[:amount_cents],
+            currency: session_params[:currency] || @params[:currency] || "RUB"
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
+    def error_result(message)
+      errors = ActiveModel::Errors.new(Request.new)
+      errors.add(:base, message)
+      { success: false, errors: errors }
+    end
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..cf498d5 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -10,6 +10,7 @@
       patch :default, on: :member, action: :set_default
     end
 
+    post "requests/bulk", to: "requests#bulk_create"
     resources :requests, only: [:index, :show, :create] do
       member do
         patch :confirm
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..59cc01f 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -93,6 +93,53 @@
     end
   end
 
+  describe "POST /api/requests/bulk" do
+    let(:base_time) { 3.days.from_now }
+
+    let(:bulk_params) do
+      {
+        provider_id: provider.id,
+        duration_minutes: 120,
+        amount_cents: 350_000,
+        currency: "RUB",
+        location: "123 Main St",
+        notes: "Weekly session",
+        sessions: 5.times.map { |i|
+          { scheduled_at: (base_time + i.weeks).iso8601 }
+        }
+      }
+    end
+
+    it "creates 5 requests at once" do
+      post "/api/requests/bulk", params: bulk_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["requests"].length).to eq(5)
+      expect(body["requests"]).to all(include("state" => "pending"))
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
+    it "returns error when sessions count is wrong" do
+      bad_params = bulk_params.merge(sessions: [{ scheduled_at: base_time.iso8601 }])
+      post "/api/requests/bulk", params: bad_params, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 401 without auth" do
+      post "/api/requests/bulk", params: bulk_params
+      expect(response).to have_http_status(:unauthorized)
+    end
+  end
+
   describe "PATCH /api/requests/:id/confirm" do
     let(:request) { create(:request, client: client, provider: provider) }
 
diff --git a/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb b/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb
new file mode 100644
index 0000000..6d03f03
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/bulk_create_service_spec.rb
@@ -0,0 +1,103 @@
+require "rails_helper"
+
+RSpec.describe Requests::BulkCreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:base_time) { 3.days.from_now }
+
+  let(:sessions) do
+    5.times.map do |i|
+      {
+        scheduled_at: base_time + i.weeks,
+        duration_minutes: 120,
+        amount_cents: 350_000,
+        currency: "RUB"
+      }
+    end
+  end
+
+  let(:params) do
+    {
+      location: "123 Main St",
+      notes: "Weekly session",
+      sessions: sessions
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: params).call }
+
+  describe "#call" do
+    context "with valid params" do
+      it "creates 5 requests in pending state" do
+        expect { result }.to change(Request, :count).by(5)
+        expect(result[:success]).to be true
+        expect(result[:requests].length).to eq(5)
+        expect(result[:requests]).to all(have_attributes(state: "pending"))
+      end
+
+      it "creates a payment for each request" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:requests].each do |request|
+          payment = request.payment
+          expect(payment.status).to eq("pending")
+          expect(payment.fee_cents).to eq(35_000)
+          expect(payment.amount_cents).to eq(350_000)
+        end
+      end
+
+      it "schedules sessions weekly" do
+        times = result[:requests].map(&:scheduled_at)
+        times.each_cons(2) do |a, b|
+          expect(b - a).to be_within(1.second).of(1.week)
+        end
+      end
+
+      it "shares location and notes across sessions" do
+        result[:requests].each do |request|
+          expect(request.location).to eq("123 Main St")
+          expect(request.notes).to eq("Weekly session")
+        end
+      end
+
+      it "notifies the provider for each request" do
+        result
+        log = read_notification_log
+        # Each notification generates 3 channel entries (push, sms, email)
+        expect(log.scan("event=request_created").count).to eq(15)
+      end
+    end
+
+    context "with missing sessions" do
+      let(:params) { { location: "123 Main St" } }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors].full_messages).to include("Sessions are required")
+      end
+    end
+
+    context "with wrong number of sessions" do
+      let(:sessions) do
+        3.times.map do |i|
+          { scheduled_at: base_time + i.weeks, duration_minutes: 120, amount_cents: 350_000, currency: "RUB" }
+        end
+      end
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors].full_messages).to include("Exactly 5 sessions are required")
+      end
+    end
+
+    context "with invalid session data" do
+      let(:sessions) do
+        5.times.map { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
+      end
+
+      it "rolls back all requests on failure" do
+        expect { result }.not_to change(Request, :count)
+        expect(result[:success]).to be false
+      end
+    end
+  end
+end
```
