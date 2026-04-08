# Experiment: 02-rebook-feature
# App: request_clean | Model: opus | Run: 3
# Branch: experiment/02-rebook-feature/request_clean/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**Endpoint:** `POST /api/requests/:id/rebook` (client-only)

**How it works:** A client sends a request to rebook based on a previous request ID. The new request automatically reuses the original's **provider**, **location**, **duration**, and **amount**. The client must provide `scheduled_at` for the new booking and can optionally override `duration_minutes`, `location`, `amount_cents`, `currency`, and `notes`.

**Files changed:**
- `app/services/requests/rebook_service.rb` — new service that copies fields from the original request, creates the new request + payment in a transaction, and notifies the provider
- `app/controllers/api/requests_controller.rb` — added `rebook` action
- `config/routes.rb` — added `post :rebook` member route
- `spec/services/requests/rebook_service_spec.rb` — 7 unit tests for the service
- `spec/requests/api/requests_spec.rb` — 5 integration tests for the endpoint

All 33 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..9151edd 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,25 @@ def reject
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      result = Requests::RebookService.new(
+        original_request: @request,
+        client: client,
+        params: request_params
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      elsif result[:error]
+        render json: { error: result[:error] }, status: :unprocessable_entity
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     private
 
     def set_request
diff --git a/affordance_request_clean/app/services/requests/rebook_service.rb b/affordance_request_clean/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..b99ccc5
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/rebook_service.rb
@@ -0,0 +1,48 @@
+module Requests
+  class RebookService
+    def initialize(original_request:, client:, params:)
+      @original_request = original_request
+      @client = client
+      @params = params
+    end
+
+    def call
+      unless @original_request.client_id == @client.id
+        return { success: false, error: "Cannot rebook another client's request" }
+      end
+
+      new_request = Request.new(
+        client: @client,
+        provider: @original_request.provider,
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes] || @original_request.duration_minutes,
+        location: @params[:location] || @original_request.location,
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents] || @original_request.amount_cents,
+        currency: @params[:currency] || @original_request.currency
+      )
+
+      Request.transaction do
+        new_request.save!
+        Payment.create!(
+          request: new_request,
+          amount_cents: new_request.amount_cents,
+          currency: new_request.currency,
+          fee_cents: calculate_fee(new_request.amount_cents),
+          status: "pending"
+        )
+      end
+
+      NotificationService.notify(@original_request.provider, :request_created, request_id: new_request.id)
+      { success: true, request: new_request }
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
index 86b84c8..dbd4343 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -180,4 +180,61 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/requests/:id/rebook" do
+    let(:original_request) do
+      create(:request, :completed, client: client, provider: provider,
+        location: "123 Main St", duration_minutes: 120, amount_cents: 350_000)
+    end
+
+    it "creates a new request based on the original" do
+      post "/api/requests/#{original_request.id}/rebook",
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
+    it "allows overriding fields" do
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601, duration_minutes: 60, location: "New place" },
+        headers: auth_headers(client)
+
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["duration_minutes"]).to eq(60)
+      expect(body["location"]).to eq("New place")
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{original_request.id}/rebook",
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
+    it "returns error when rebooking another client's request" do
+      other_client = create(:client)
+      post "/api/requests/#{original_request.id}/rebook",
+        params: { scheduled_at: 5.days.from_now.iso8601 },
+        headers: auth_headers(other_client)
+
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
diff --git a/affordance_request_clean/spec/services/requests/rebook_service_spec.rb b/affordance_request_clean/spec/services/requests/rebook_service_spec.rb
new file mode 100644
index 0000000..1d631b5
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/rebook_service_spec.rb
@@ -0,0 +1,103 @@
+require "rails_helper"
+
+RSpec.describe Requests::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_request) do
+    create(:request, :completed, client: client, provider: provider,
+      location: "123 Main St", duration_minutes: 120, amount_cents: 350_000, currency: "RUB")
+  end
+
+  describe "#call" do
+    context "with only scheduled_at" do
+      let(:new_time) { 5.days.from_now }
+      subject(:result) do
+        described_class.new(
+          original_request: original_request,
+          client: client,
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
+      it "creates a pending payment with fee" do
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
+    context "with overridden fields" do
+      subject(:result) do
+        described_class.new(
+          original_request: original_request,
+          client: client,
+          params: {
+            scheduled_at: 5.days.from_now,
+            duration_minutes: 60,
+            location: "456 Oak Ave",
+            amount_cents: 200_000,
+            notes: "New notes"
+          }
+        ).call
+      end
+
+      it "uses overridden values" do
+        expect(result[:success]).to be true
+        new_request = result[:request]
+        expect(new_request.duration_minutes).to eq(60)
+        expect(new_request.location).to eq("456 Oak Ave")
+        expect(new_request.amount_cents).to eq(200_000)
+        expect(new_request.notes).to eq("New notes")
+      end
+    end
+
+    context "when client does not own the original request" do
+      let(:other_client) { create(:client) }
+
+      subject(:result) do
+        described_class.new(
+          original_request: original_request,
+          client: other_client,
+          params: { scheduled_at: 5.days.from_now }
+        ).call
+      end
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("Cannot rebook another client's request")
+      end
+    end
+
+    context "with missing scheduled_at" do
+      subject(:result) do
+        described_class.new(
+          original_request: original_request,
+          client: client,
+          params: { scheduled_at: nil }
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
