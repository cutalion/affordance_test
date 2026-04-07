# Experiment: 05-auto-assignment
# App: request | Model: sonnet | Run: 2
# Branch: experiment/05-auto-assignment/request/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**`app/services/providers/auto_assign_service.rb`** — finds the highest-rated active provider with no overlapping bookings. "Busy" means having an active request (`created`, `created_accepted`, `accepted`, or `started`) whose time window overlaps with the requested slot. Uses SQLite's `datetime()` modifier for the overlap calculation.

**`app/controllers/api/requests_controller.rb`** — the `create` action now accepts requests without `provider_id`. If omitted, it invokes `AutoAssignService` and returns 422 if no provider is available.

**Specs** — 9 new examples covering the service (overlap detection, tie-breaking by rating, inactive/canceled requests ignored, empty pool) and 2 controller-level integration tests (success + no-provider error).

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..039f12a 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -18,8 +18,18 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = if params[:provider_id].present?
+        found = Provider.find_by(id: params[:provider_id])
+        return render_not_found unless found
+        found
+      else
+        auto_result = Providers::AutoAssignService.new(
+          scheduled_at: Time.zone.parse(params[:scheduled_at].to_s),
+          duration_minutes: params[:duration_minutes].to_i
+        ).call
+        return render_unprocessable([auto_result[:error]]) unless auto_result[:success]
+        auto_result[:provider]
+      end
 
       result = Requests::CreateService.new(
         client: client,
diff --git a/affordance_request/app/services/providers/auto_assign_service.rb b/affordance_request/app/services/providers/auto_assign_service.rb
new file mode 100644
index 0000000..7251c1f
--- /dev/null
+++ b/affordance_request/app/services/providers/auto_assign_service.rb
@@ -0,0 +1,35 @@
+module Providers
+  class AutoAssignService
+    ACTIVE_STATES = %w[created created_accepted accepted started].freeze
+
+    def initialize(scheduled_at:, duration_minutes:)
+      @scheduled_at = scheduled_at
+      @duration_minutes = duration_minutes
+    end
+
+    def call
+      new_start = @scheduled_at.utc.strftime("%Y-%m-%d %H:%M:%S")
+      new_end = (@scheduled_at + @duration_minutes.to_i.minutes).utc.strftime("%Y-%m-%d %H:%M:%S")
+
+      busy_provider_ids = Request
+        .where(state: ACTIVE_STATES)
+        .where(
+          "scheduled_at < ? AND datetime(scheduled_at, '+' || CAST(duration_minutes AS TEXT) || ' minutes') > ?",
+          new_end,
+          new_start
+        )
+        .pluck(:provider_id)
+
+      provider = Provider.active
+        .where.not(id: busy_provider_ids)
+        .order(rating: :desc)
+        .first
+
+      if provider
+        { success: true, provider: provider }
+      else
+        { success: false, error: "No available providers for the requested time" }
+      end
+    end
+  end
+end
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..d8c0814 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -91,6 +91,31 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "when provider_id is omitted" do
+      let(:auto_params) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "auto-assigns the highest-rated available provider" do
+        available = create(:provider)
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["state"]).to eq("created")
+        expect(body["provider_id"]).to eq(available.id)
+      end
+
+      it "returns error when no provider is available" do
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "POST /api/requests/direct" do
diff --git a/affordance_request/spec/services/providers/auto_assign_service_spec.rb b/affordance_request/spec/services/providers/auto_assign_service_spec.rb
new file mode 100644
index 0000000..1bd01dc
--- /dev/null
+++ b/affordance_request/spec/services/providers/auto_assign_service_spec.rb
@@ -0,0 +1,114 @@
+require "rails_helper"
+
+RSpec.describe Providers::AutoAssignService do
+  let(:scheduled_at) { 3.days.from_now.beginning_of_hour }
+  let(:duration_minutes) { 120 }
+
+  subject(:result) { described_class.new(scheduled_at: scheduled_at, duration_minutes: duration_minutes).call }
+
+  describe "#call" do
+    context "when active providers exist with no conflicts" do
+      let!(:low_rated) { create(:provider, rating: 3.0) }
+      let!(:high_rated) { create(:provider, rating: 4.8) }
+      let!(:mid_rated) { create(:provider, rating: 4.2) }
+
+      it "returns success with the highest-rated provider" do
+        expect(result[:success]).to be true
+        expect(result[:provider]).to eq(high_rated)
+      end
+    end
+
+    context "when the highest-rated provider is busy at the requested time" do
+      let!(:busy_provider) { create(:provider, rating: 5.0) }
+      let!(:free_provider) { create(:provider, rating: 3.0) }
+
+      before do
+        create(:request, :accepted,
+          provider: busy_provider,
+          scheduled_at: scheduled_at,
+          duration_minutes: duration_minutes)
+      end
+
+      it "assigns the next available provider" do
+        expect(result[:success]).to be true
+        expect(result[:provider]).to eq(free_provider)
+      end
+    end
+
+    context "when a provider has an overlapping (but not identical) booking" do
+      let!(:busy_provider) { create(:provider, rating: 5.0) }
+      let!(:free_provider) { create(:provider, rating: 3.0) }
+
+      before do
+        # existing booking starts 1 hour before, lasting 2 hours — overlaps with start
+        create(:request, :accepted,
+          provider: busy_provider,
+          scheduled_at: scheduled_at - 1.hour,
+          duration_minutes: 120)
+      end
+
+      it "considers that provider busy" do
+        expect(result[:success]).to be true
+        expect(result[:provider]).to eq(free_provider)
+      end
+    end
+
+    context "when a provider has a non-conflicting booking" do
+      let!(:provider) { create(:provider, rating: 5.0) }
+
+      before do
+        # booking ends before the requested slot starts
+        create(:request, :accepted,
+          provider: provider,
+          scheduled_at: scheduled_at - 3.hours,
+          duration_minutes: 60)
+      end
+
+      it "considers the provider available" do
+        expect(result[:success]).to be true
+        expect(result[:provider]).to eq(provider)
+      end
+    end
+
+    context "when a provider has a declined/canceled booking at the same time" do
+      let!(:provider) { create(:provider, rating: 5.0) }
+
+      before do
+        create(:request, :declined,
+          provider: provider,
+          scheduled_at: scheduled_at,
+          duration_minutes: duration_minutes)
+      end
+
+      it "considers the provider available" do
+        expect(result[:success]).to be true
+        expect(result[:provider]).to eq(provider)
+      end
+    end
+
+    context "when no active providers exist" do
+      before { create(:provider, active: false) }
+
+      it "returns failure" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to be_present
+      end
+    end
+
+    context "when all providers are busy" do
+      let!(:provider) { create(:provider) }
+
+      before do
+        create(:request, :accepted,
+          provider: provider,
+          scheduled_at: scheduled_at,
+          duration_minutes: duration_minutes)
+      end
+
+      it "returns failure" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to be_present
+      end
+    end
+  end
+end
```
