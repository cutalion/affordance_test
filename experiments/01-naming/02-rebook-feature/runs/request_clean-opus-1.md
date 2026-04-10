# Experiment: 02-rebook-feature
# App: request_clean | Model: opus | Run: 1
# Branch: experiment/02-rebook-feature/request_clean/opus/run-1

---

## Claude Output

Done. Here's what was implemented:

**Endpoint:** `POST /api/requests/:id/rebook` (client-only)

**How it works:** A client sends a request with a previous request ID and a new `scheduled_at`. The service copies `provider`, `location`, `duration_minutes`, `amount_cents`, and `currency` from the original request. All copied fields can be optionally overridden. A new pending payment with 10% fee is created, and the provider is notified.

**Files changed:**
- `app/services/requests/rebook_service.rb` — new service
- `app/controllers/api/requests_controller.rb` — `rebook` action
- `config/routes.rb` — `post :rebook` member route
- `spec/services/requests/rebook_service_spec.rb` — service tests (4 examples)
- `spec/requests/api/requests_spec.rb` — integration tests (5 examples)

All 275 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..558f800 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,23 @@ def reject
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      result = Requests::RebookService.new(
+        client: client,
+        previous_request: @request,
+        params: rebook_params
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     private
 
     def set_request
@@ -109,6 +126,10 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request_clean/app/services/requests/rebook_service.rb b/affordance_request_clean/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..85725e0
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/rebook_service.rb
@@ -0,0 +1,44 @@
+module Requests
+  class RebookService
+    def initialize(client:, previous_request:, params:)
+      @client = client
+      @previous_request = previous_request
+      @params = params
+    end
+
+    def call
+      request = Request.new(
+        client: @client,
+        provider: @previous_request.provider,
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes] || @previous_request.duration_minutes,
+        location: @params[:location] || @previous_request.location,
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents] || @previous_request.amount_cents,
+        currency: @params[:currency] || @previous_request.currency
+      )
+
+      Request.transaction do
+        request.save!
+        Payment.create!(
+          request: request,
+          amount_cents: request.amount_cents,
+          currency: request.currency,
+          fee_cents: calculate_fee(request.amount_cents),
+          status: "pending"
+        )
+      end
+
+      NotificationService.notify(@previous_request.provider, :request_created, request_id: request.id)
+      { success: true, request: request }
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
index 06454f8..564cfee 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -17,6 +17,7 @@
         patch :complete
         patch :cancel
         patch :reject
+        post :rebook
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..00d80cc 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -180,4 +180,60 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/requests/:id/rebook" do
+    let(:previous_request) do
+      create(:request, :completed, client: client, provider: provider,
+        location: "123 Main St", duration_minutes: 120, amount_cents: 350_000)
+    end
+
+    it "creates a new request based on a previous one" do
+      post "/api/requests/#{previous_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(120)
+      expect(body["amount_cents"]).to eq(350_000)
+    end
+
+    it "allows overriding duration and location" do
+      post "/api/requests/#{previous_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601, duration_minutes: 60, location: "456 Oak Ave" },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["duration_minutes"]).to eq(60)
+      expect(body["location"]).to eq("456 Oak Ave")
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{previous_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(provider)
+
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns 404 for unknown request" do
+      post "/api/requests/99999/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:not_found)
+    end
+
+    it "returns validation errors without scheduled_at" do
+      post "/api/requests/#{previous_request.id}/rebook",
+        params: {},
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
diff --git a/affordance_request_clean/spec/services/requests/rebook_service_spec.rb b/affordance_request_clean/spec/services/requests/rebook_service_spec.rb
new file mode 100644
index 0000000..d6cf82e
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/rebook_service_spec.rb
@@ -0,0 +1,79 @@
+require "rails_helper"
+
+RSpec.describe Requests::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:previous_request) do
+    create(:request, :completed, client: client, provider: provider,
+      location: "123 Main St", duration_minutes: 120, amount_cents: 350_000, currency: "RUB")
+  end
+
+  describe "#call" do
+    context "with only scheduled_at" do
+      let(:new_time) { 5.days.from_now }
+      subject(:result) do
+        described_class.new(
+          client: client,
+          previous_request: previous_request,
+          params: { scheduled_at: new_time }
+        ).call
+      end
+
+      it "creates a new request reusing provider, location, and duration" do
+        expect(result[:success]).to be true
+        new_request = result[:request]
+        expect(new_request.provider).to eq(provider)
+        expect(new_request.location).to eq("123 Main St")
+        expect(new_request.duration_minutes).to eq(120)
+        expect(new_request.amount_cents).to eq(350_000)
+        expect(new_request.currency).to eq("RUB")
+        expect(new_request.state).to eq("pending")
+      end
+
+      it "creates a pending payment" do
+        expect { result }.to change(Payment, :count).by(1)
+        payment = result[:request].payment
+        expect(payment.status).to eq("pending")
+        expect(payment.fee_cents).to eq(35_000)
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=request_created")
+      end
+    end
+
+    context "with overridden params" do
+      subject(:result) do
+        described_class.new(
+          client: client,
+          previous_request: previous_request,
+          params: { scheduled_at: 5.days.from_now, duration_minutes: 60, location: "456 Oak Ave", notes: "New notes" }
+        ).call
+      end
+
+      it "uses overridden values instead of previous request values" do
+        expect(result[:success]).to be true
+        new_request = result[:request]
+        expect(new_request.duration_minutes).to eq(60)
+        expect(new_request.location).to eq("456 Oak Ave")
+        expect(new_request.notes).to eq("New notes")
+      end
+    end
+
+    context "without scheduled_at" do
+      subject(:result) do
+        described_class.new(
+          client: client,
+          previous_request: previous_request,
+          params: {}
+        ).call
+      end
+
+      it "returns validation errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+    end
+  end
+end
```
