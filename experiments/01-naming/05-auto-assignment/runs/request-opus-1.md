# Experiment: 05-auto-assignment
# App: request | Model: opus | Run: 1
# Branch: experiment/05-auto-assignment/request/opus/run-1

---

## Claude Output

Done. Here's what I implemented:

**`app/services/providers/auto_assign_service.rb`** — Finds the highest-rated active provider with no overlapping bookings at the requested time. It checks for time conflicts against requests in active states (created, created_accepted, accepted, started) and ignores canceled/declined/rejected/missed ones.

**`app/controllers/api/requests_controller.rb`** — Modified `create` to make `provider_id` optional. When omitted, calls `AutoAssignService` to pick a provider. Returns 422 if no provider is available.

**Tests added:**
- 5 unit tests for `AutoAssignService` (highest-rated selection, busy provider exclusion, canceled request handling, inactive provider exclusion, no providers available)
- 2 integration tests for the API endpoint (auto-assigns best provider, returns error when none available)

All 297 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..ef42333 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -18,8 +18,16 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      if params[:provider_id].present?
+        provider = Provider.find_by(id: params[:provider_id])
+        return render_not_found unless provider
+      else
+        provider = Providers::AutoAssignService.new(
+          scheduled_at: params[:scheduled_at],
+          duration_minutes: params[:duration_minutes]
+        ).call
+        return render_unprocessable(["No available provider found"]) unless provider
+      end
 
       result = Requests::CreateService.new(
         client: client,
diff --git a/affordance_request/app/services/providers/auto_assign_service.rb b/affordance_request/app/services/providers/auto_assign_service.rb
new file mode 100644
index 0000000..7989b41
--- /dev/null
+++ b/affordance_request/app/services/providers/auto_assign_service.rb
@@ -0,0 +1,27 @@
+module Providers
+  class AutoAssignService
+    def initialize(scheduled_at:, duration_minutes:)
+      @scheduled_at = Time.zone.parse(scheduled_at.to_s)
+      @duration_minutes = duration_minutes.to_i
+    end
+
+    def call
+      Provider.active
+        .where.not(id: busy_provider_ids)
+        .order(rating: :desc)
+        .first
+    end
+
+    private
+
+    def busy_provider_ids
+      booking_end = @scheduled_at + @duration_minutes.minutes
+
+      Request.where(state: %w[created created_accepted accepted started])
+        .where("scheduled_at < :booking_end AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > :booking_start",
+          booking_start: @scheduled_at,
+          booking_end: booking_end)
+        .select(:provider_id)
+    end
+  end
+end
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..f8888c0 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -91,6 +91,34 @@
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
+      it "auto-assigns the highest-rated available provider" do
+        create(:provider, rating: 3.0)
+        best = create(:provider, rating: 4.9)
+
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(best.id)
+      end
+
+      it "returns error when no provider is available" do
+        Provider.destroy_all
+
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "POST /api/requests/direct" do
diff --git a/affordance_request/spec/services/providers/auto_assign_service_spec.rb b/affordance_request/spec/services/providers/auto_assign_service_spec.rb
new file mode 100644
index 0000000..cbe053c
--- /dev/null
+++ b/affordance_request/spec/services/providers/auto_assign_service_spec.rb
@@ -0,0 +1,69 @@
+require "rails_helper"
+
+RSpec.describe Providers::AutoAssignService do
+  let(:scheduled_at) { 3.days.from_now }
+  let(:duration_minutes) { 120 }
+
+  subject do
+    described_class.new(scheduled_at: scheduled_at, duration_minutes: duration_minutes).call
+  end
+
+  context "when providers are available" do
+    let!(:low_rated) { create(:provider, rating: 3.0) }
+    let!(:high_rated) { create(:provider, rating: 4.8) }
+    let!(:mid_rated) { create(:provider, rating: 4.2) }
+
+    it "returns the highest-rated provider" do
+      expect(subject).to eq(high_rated)
+    end
+  end
+
+  context "when a provider is busy at the requested time" do
+    let!(:busy_provider) { create(:provider, rating: 5.0) }
+    let!(:free_provider) { create(:provider, rating: 4.0) }
+
+    before do
+      create(:request,
+        provider: busy_provider,
+        client: create(:client),
+        scheduled_at: scheduled_at - 30.minutes,
+        duration_minutes: 120,
+        state: "accepted")
+    end
+
+    it "skips the busy provider and returns the free one" do
+      expect(subject).to eq(free_provider)
+    end
+  end
+
+  context "when a provider has a non-blocking request (canceled)" do
+    let!(:provider) { create(:provider, rating: 5.0) }
+
+    before do
+      create(:request, :canceled,
+        provider: provider,
+        client: create(:client),
+        scheduled_at: scheduled_at,
+        duration_minutes: 120)
+    end
+
+    it "considers the provider available" do
+      expect(subject).to eq(provider)
+    end
+  end
+
+  context "when an inactive provider exists" do
+    let!(:inactive_provider) { create(:provider, rating: 5.0, active: false) }
+    let!(:active_provider) { create(:provider, rating: 3.0) }
+
+    it "only returns active providers" do
+      expect(subject).to eq(active_provider)
+    end
+  end
+
+  context "when no providers are available" do
+    it "returns nil" do
+      expect(subject).to be_nil
+    end
+  end
+end
```
