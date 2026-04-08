# Experiment: 05-auto-assignment
# App: request_clean | Model: opus | Run: 3
# Branch: experiment/05-auto-assignment/request_clean/opus/run-3

---

## Claude Output

Done. Here's what I implemented:

**Provider model** (`app/models/provider.rb`): Added `highest_rated` scope — filters to active providers, ordered by rating descending.

**CreateService** (`app/services/requests/create_service.rb`): When `provider` is `nil`, calls `assign_provider` which picks the highest-rated active provider. Returns an error if none are available.

**Controller** (`app/controllers/api/requests_controller.rb`): `provider_id` is now optional. If omitted, the service handles auto-assignment. If provided but invalid, still returns 404.

**Tests**: 5 new tests covering:
- `Provider.highest_rated` scope (excludes inactive, orders by rating)
- Service auto-assigns highest-rated provider when none given
- Service returns error when no active providers exist
- API endpoint auto-assigns when `provider_id` omitted
- API endpoint returns 422 when no providers available

All 270 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..94fc9c6 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -18,8 +18,11 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = nil
+      if params[:provider_id].present?
+        provider = Provider.find_by(id: params[:provider_id])
+        return render_not_found unless provider
+      end
 
       result = Requests::CreateService.new(
         client: client,
@@ -30,7 +33,7 @@ def create
       if result[:success]
         render json: request_detail_json(result[:request]), status: :created
       else
-        render_unprocessable(result[:errors].full_messages)
+        render_unprocessable(Array(result[:errors]).map { |e| e.respond_to?(:full_messages) ? e.full_messages : e }.flatten)
       end
     end
 
diff --git a/affordance_request_clean/app/models/provider.rb b/affordance_request_clean/app/models/provider.rb
index 0f43919..ac7320a 100644
--- a/affordance_request_clean/app/models/provider.rb
+++ b/affordance_request_clean/app/models/provider.rb
@@ -12,6 +12,7 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :highest_rated, -> { active.order(rating: :desc) }
 
   private
 
diff --git a/affordance_request_clean/app/services/requests/create_service.rb b/affordance_request_clean/app/services/requests/create_service.rb
index 0314a96..8d90a9f 100644
--- a/affordance_request_clean/app/services/requests/create_service.rb
+++ b/affordance_request_clean/app/services/requests/create_service.rb
@@ -7,9 +7,12 @@ def initialize(client:, provider:, params:)
     end
 
     def call
+      provider = @provider || assign_provider
+      return { success: false, errors: ["No available provider"] } unless provider
+
       request = Request.new(
         client: @client,
-        provider: @provider,
+        provider: provider,
         scheduled_at: @params[:scheduled_at],
         duration_minutes: @params[:duration_minutes],
         location: @params[:location],
@@ -29,7 +32,7 @@ def call
         )
       end
 
-      NotificationService.notify(@provider, :request_created, request_id: request.id)
+      NotificationService.notify(provider, :request_created, request_id: request.id)
       { success: true, request: request }
     rescue ActiveRecord::RecordInvalid => e
       { success: false, errors: e.record.errors }
@@ -37,6 +40,10 @@ def call
 
     private
 
+    def assign_provider
+      Provider.highest_rated.first
+    end
+
     def calculate_fee(amount_cents)
       (amount_cents * 0.1).to_i
     end
diff --git a/affordance_request_clean/spec/models/provider_spec.rb b/affordance_request_clean/spec/models/provider_spec.rb
index ad86fbe..5e2ef73 100644
--- a/affordance_request_clean/spec/models/provider_spec.rb
+++ b/affordance_request_clean/spec/models/provider_spec.rb
@@ -59,6 +59,19 @@
     end
   end
 
+  describe ".highest_rated scope" do
+    it "returns active providers ordered by rating descending" do
+      low = create(:provider, rating: 2.0, active: true)
+      high = create(:provider, rating: 5.0, active: true)
+      mid = create(:provider, rating: 3.5, active: true)
+      inactive = create(:provider, rating: 5.0, active: false)
+
+      result = Provider.highest_rated
+      expect(result).to eq([high, mid, low])
+      expect(result).not_to include(inactive)
+    end
+  end
+
   describe "notification_preferences" do
     it "has default notification preferences" do
       provider = create(:provider)
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..7068fae 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -91,6 +91,32 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id (auto-assignment)" do
+      let(:auto_params) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "auto-assigns the highest-rated active provider" do
+        create(:provider, rating: 3.0, active: true)
+        best = create(:provider, rating: 5.0, active: true)
+
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(best.id)
+      end
+
+      it "returns error when no providers are available" do
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "PATCH /api/requests/:id/confirm" do
diff --git a/affordance_request_clean/spec/services/requests/create_service_spec.rb b/affordance_request_clean/spec/services/requests/create_service_spec.rb
index 9e9fd30..067a266 100644
--- a/affordance_request_clean/spec/services/requests/create_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/create_service_spec.rb
@@ -45,5 +45,26 @@
         expect(result[:errors]).to be_present
       end
     end
+
+    context "without a provider (auto-assignment)" do
+      subject(:result) { described_class.new(client: client, provider: nil, params: valid_params).call }
+
+      it "assigns the highest-rated active provider" do
+        create(:provider, rating: 3.0, active: true)
+        best = create(:provider, rating: 5.0, active: true)
+        create(:provider, rating: 4.0, active: false)
+
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(best)
+      end
+
+      it "returns error when no active providers exist" do
+        create(:provider, active: false)
+
+        result = described_class.new(client: client, provider: nil, params: valid_params).call
+        expect(result[:success]).to be false
+        expect(result[:errors]).to include("No available provider")
+      end
+    end
   end
 end
```
