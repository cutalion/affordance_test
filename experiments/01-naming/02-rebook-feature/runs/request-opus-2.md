# Experiment: 02-rebook-feature
# App: request | Model: opus | Run: 2
# Branch: experiment/02-rebook-feature/request/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**`POST /api/requests/:id/rebook`** — client-only endpoint that creates a new booking based on a previous request.

- **Reuses** from original: provider, location, duration, currency
- **Required**: `scheduled_at`, `amount_cents`
- **Optional overrides**: `location`, `duration_minutes`, `notes`, `currency`
- Creates a pending payment with 10% fee (same as regular create)
- Validates client owns the original request
- All 37 specs pass (8 new: 3 service + 5 request)

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..921f7f5 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject, :rebook]
 
     def index
       requests = scoped_requests
@@ -118,6 +118,27 @@ def reject
       handle_service_result(result)
     end
 
+    def rebook
+      client = current_client!
+      return if performed?
+
+      unless @the_request.client_id == client.id
+        return render json: { error: "Can only rebook your own requests" }, status: :unprocessable_entity
+      end
+
+      result = Requests::RebookService.new(
+        original_request: @the_request,
+        client: client,
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
@@ -137,6 +158,10 @@ def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
 
+    def rebook_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+    end
+
     def handle_service_result(result)
       if result[:success]
         render json: request_detail_json(result[:request])
diff --git a/affordance_request/app/services/requests/rebook_service.rb b/affordance_request/app/services/requests/rebook_service.rb
new file mode 100644
index 0000000..a83b9ef
--- /dev/null
+++ b/affordance_request/app/services/requests/rebook_service.rb
@@ -0,0 +1,44 @@
+module Requests
+  class RebookService
+    def initialize(original_request:, client:, params:)
+      @original_request = original_request
+      @client = client
+      @params = params
+    end
+
+    def call
+      request = Request.new(
+        client: @client,
+        provider: @original_request.provider,
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes] || @original_request.duration_minutes,
+        location: @params[:location] || @original_request.location,
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents],
+        currency: @params[:currency] || @original_request.currency
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
+      NotificationService.notify(@original_request.provider, :request_created, request_id: request.id)
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
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..4a162af 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -21,6 +21,7 @@
         patch :fulfill
         patch :cancel
         patch :reject
+        post :rebook
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..2010123 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -224,4 +224,52 @@
       expect(response).to have_http_status(:unprocessable_entity)
     end
   end
+
+  describe "POST /api/requests/:id/rebook" do
+    let(:original) { create(:request, :fulfilled, client: client, provider: provider, location: "123 Main St", duration_minutes: 120) }
+
+    it "creates a new request reusing provider, location, and duration" do
+      post "/api/requests/#{original.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601, amount_cents: 350_000 },
+           headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("created")
+      expect(body["provider_id"]).to eq(provider.id)
+      expect(body["location"]).to eq("123 Main St")
+      expect(body["duration_minutes"]).to eq(120)
+    end
+
+    it "allows overriding location and duration" do
+      post "/api/requests/#{original.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601, amount_cents: 400_000, location: "New Place", duration_minutes: 60 },
+           headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["location"]).to eq("New Place")
+      expect(body["duration_minutes"]).to eq(60)
+    end
+
+    it "returns 403 for provider" do
+      post "/api/requests/#{original.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601, amount_cents: 350_000 },
+           headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+
+    it "returns error when rebooking another client's request" do
+      other_client = create(:client)
+      post "/api/requests/#{original.id}/rebook",
+           params: { scheduled_at: 5.days.from_now.iso8601, amount_cents: 350_000 },
+           headers: auth_headers(other_client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns validation errors for missing scheduled_at" do
+      post "/api/requests/#{original.id}/rebook",
+           params: { amount_cents: 350_000 },
+           headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+  end
 end
diff --git a/affordance_request/spec/services/requests/rebook_service_spec.rb b/affordance_request/spec/services/requests/rebook_service_spec.rb
new file mode 100644
index 0000000..9b3c3b6
--- /dev/null
+++ b/affordance_request/spec/services/requests/rebook_service_spec.rb
@@ -0,0 +1,62 @@
+require "rails_helper"
+
+RSpec.describe Requests::RebookService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:original_request) do
+    create(:request, client: client, provider: provider,
+           location: "123 Main St", duration_minutes: 120,
+           amount_cents: 350_000, currency: "RUB")
+  end
+
+  describe "#call" do
+    context "with scheduled_at and amount_cents provided" do
+      let(:params) { { scheduled_at: 5.days.from_now, amount_cents: 350_000 } }
+      subject(:result) { described_class.new(original_request: original_request, client: client, params: params).call }
+
+      it "creates a new request reusing provider, location, and duration" do
+        expect(result[:success]).to be true
+        new_request = result[:request]
+        expect(new_request.provider).to eq(provider)
+        expect(new_request.location).to eq("123 Main St")
+        expect(new_request.duration_minutes).to eq(120)
+        expect(new_request.state).to eq("created")
+      end
+
+      it "creates a pending payment" do
+        expect { result }.to change(Payment, :count).by(1)
+        payment = result[:request].payment
+        expect(payment.status).to eq("pending")
+        expect(payment.amount_cents).to eq(350_000)
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=request_created")
+      end
+    end
+
+    context "with overrides for location and duration" do
+      let(:params) { { scheduled_at: 5.days.from_now, amount_cents: 400_000, location: "456 Other St", duration_minutes: 60 } }
+      subject(:result) { described_class.new(original_request: original_request, client: client, params: params).call }
+
+      it "uses the overridden values" do
+        expect(result[:success]).to be true
+        new_request = result[:request]
+        expect(new_request.location).to eq("456 Other St")
+        expect(new_request.duration_minutes).to eq(60)
+        expect(new_request.amount_cents).to eq(400_000)
+      end
+    end
+
+    context "with missing required fields" do
+      let(:params) { { scheduled_at: nil, amount_cents: nil } }
+      subject(:result) { described_class.new(original_request: original_request, client: client, params: params).call }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+    end
+  end
+end
```
