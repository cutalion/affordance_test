# Experiment: 05-auto-assignment
# App: request_clean | Model: opus | Run: 2
# Branch: experiment/05-auto-assignment/request_clean/opus/run-2

---

## Claude Output

Done. Here's what I implemented:

**Provider model** (`app/models/provider.rb`):
- `highest_rated` scope — orders by rating descending
- `available_at(scheduled_at, duration_minutes)` scope — excludes providers with overlapping active bookings (pending/confirmed/in_progress)

**CreateService** (`app/services/requests/create_service.rb`):
- `provider` parameter is now optional (defaults to `nil`)
- When no provider is given, `assign_provider` finds the highest-rated active provider with no scheduling conflicts
- Returns an error if no provider is available

**Controller** (`app/controllers/api/requests_controller.rb`):
- `provider_id` is now optional in `POST /api/requests`
- If provided, validates it exists (404 if not); if omitted, delegates to auto-assignment

**Tests**: 9 new tests covering the scopes, service auto-assignment logic (highest-rated selection, inactive/busy provider skipping, no-provider error), and API endpoint behavior. All 275 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..70f0455 100644
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
diff --git a/affordance_request_clean/app/models/provider.rb b/affordance_request_clean/app/models/provider.rb
index 0f43919..4d7495d 100644
--- a/affordance_request_clean/app/models/provider.rb
+++ b/affordance_request_clean/app/models/provider.rb
@@ -12,6 +12,19 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :highest_rated, -> { order(rating: :desc) }
+  scope :available_at, ->(scheduled_at, duration_minutes) {
+    new_end = scheduled_at + duration_minutes.minutes
+    booked_provider_ids = Request
+      .where(state: [:pending, :confirmed, :in_progress])
+      .where(
+        "scheduled_at < :new_end AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > :new_start",
+        new_start: scheduled_at, new_end: new_end
+      )
+      .select(:provider_id)
+
+    where.not(id: booked_provider_ids)
+  }
 
   private
 
diff --git a/affordance_request_clean/app/services/requests/create_service.rb b/affordance_request_clean/app/services/requests/create_service.rb
index 0314a96..5722af3 100644
--- a/affordance_request_clean/app/services/requests/create_service.rb
+++ b/affordance_request_clean/app/services/requests/create_service.rb
@@ -1,15 +1,18 @@
 module Requests
   class CreateService
-    def initialize(client:, provider:, params:)
+    def initialize(client:, provider: nil, params:)
       @client = client
       @provider = provider
       @params = params
     end
 
     def call
+      provider = @provider || assign_provider
+      return { success: false, errors: no_provider_errors } unless provider
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
@@ -37,6 +40,19 @@ def call
 
     private
 
+    def assign_provider
+      Provider.active
+        .available_at(Time.zone.parse(@params[:scheduled_at].to_s), @params[:duration_minutes].to_i)
+        .highest_rated
+        .first
+    end
+
+    def no_provider_errors
+      errors = ActiveModel::Errors.new(Request.new)
+      errors.add(:provider, "no available provider found")
+      errors
+    end
+
     def calculate_fee(amount_cents)
       (amount_cents * 0.1).to_i
     end
diff --git a/affordance_request_clean/spec/models/provider_spec.rb b/affordance_request_clean/spec/models/provider_spec.rb
index ad86fbe..12a557f 100644
--- a/affordance_request_clean/spec/models/provider_spec.rb
+++ b/affordance_request_clean/spec/models/provider_spec.rb
@@ -59,6 +59,44 @@
     end
   end
 
+  describe ".highest_rated" do
+    it "returns providers ordered by rating descending" do
+      low = create(:provider, rating: 2.0)
+      high = create(:provider, rating: 5.0)
+      mid = create(:provider, rating: 3.5)
+
+      expect(Provider.highest_rated).to eq([high, mid, low])
+    end
+  end
+
+  describe ".available_at" do
+    let(:scheduled_at) { 3.days.from_now.beginning_of_hour }
+
+    it "excludes providers with overlapping requests" do
+      busy_provider = create(:provider)
+      free_provider = create(:provider)
+      create(:request, provider: busy_provider, scheduled_at: scheduled_at, duration_minutes: 120, state: "confirmed")
+
+      available = Provider.available_at(scheduled_at, 120)
+      expect(available).to include(free_provider)
+      expect(available).not_to include(busy_provider)
+    end
+
+    it "includes providers whose requests don't overlap" do
+      provider = create(:provider)
+      create(:request, provider: provider, scheduled_at: scheduled_at - 3.hours, duration_minutes: 60, state: "confirmed")
+
+      expect(Provider.available_at(scheduled_at, 120)).to include(provider)
+    end
+
+    it "ignores canceled and rejected requests" do
+      provider = create(:provider)
+      create(:request, :canceled, provider: provider, scheduled_at: scheduled_at, duration_minutes: 120)
+
+      expect(Provider.available_at(scheduled_at, 120)).to include(provider)
+    end
+  end
+
   describe "notification_preferences" do
     it "has default notification preferences" do
       provider = create(:provider)
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..f37f0a4 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -91,6 +91,25 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    it "auto-assigns highest-rated provider when provider_id is omitted" do
+      create(:provider, rating: 5.0, active: true)
+      low = create(:provider, rating: 2.0, active: true)
+      params_without_provider = request_params.except(:provider_id)
+
+      post "/api/requests", params: params_without_provider, headers: auth_headers(client)
+      expect(response).to have_http_status(:created)
+      body = JSON.parse(response.body)
+      expect(body["provider_id"]).not_to eq(low.id)
+    end
+
+    it "returns error when no provider is available for auto-assignment" do
+      params_without_provider = request_params.except(:provider_id)
+      Provider.update_all(active: false)
+
+      post "/api/requests", params: params_without_provider, headers: auth_headers(client)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
   end
 
   describe "PATCH /api/requests/:id/confirm" do
diff --git a/affordance_request_clean/spec/services/requests/create_service_spec.rb b/affordance_request_clean/spec/services/requests/create_service_spec.rb
index 9e9fd30..deb6894 100644
--- a/affordance_request_clean/spec/services/requests/create_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/create_service_spec.rb
@@ -37,6 +37,39 @@
       end
     end
 
+    context "without provider (auto-assignment)" do
+      subject(:result) { described_class.new(client: client, params: valid_params).call }
+
+      let!(:high_rated) { create(:provider, rating: 4.9, active: true) }
+      let!(:low_rated) { create(:provider, rating: 3.0, active: true) }
+
+      it "assigns the highest-rated available provider" do
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(high_rated)
+      end
+
+      it "skips inactive providers" do
+        high_rated.update!(active: false)
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(low_rated)
+      end
+
+      it "skips providers with overlapping requests" do
+        create(:request, provider: high_rated,
+          scheduled_at: valid_params[:scheduled_at],
+          duration_minutes: 120, state: "confirmed")
+
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(low_rated)
+      end
+
+      it "returns error when no provider is available" do
+        Provider.update_all(active: false)
+        expect(result[:success]).to be false
+        expect(result[:errors][:provider]).to include("no available provider found")
+      end
+    end
+
     context "with invalid params" do
       let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
 
```
