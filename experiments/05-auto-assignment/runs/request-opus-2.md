# Experiment: 05-auto-assignment
# App: request | Model: opus | Run: 2
# Branch: experiment/05-auto-assignment/request/opus/run-2

---

## Claude Output

Done. Here's what I implemented:

**Provider model** (`app/models/provider.rb`):
- `.available_at(scheduled_at, duration_minutes)` scope — finds active providers without overlapping active requests (created, created_accepted, accepted, or started)
- `.highest_rated_available(scheduled_at:, duration_minutes:)` — returns the top-rated provider from that scope

**Controller** (`app/controllers/api/requests_controller.rb`):
- Modified `create` action: when `provider_id` is omitted, calls `Provider.highest_rated_available` to auto-assign
- Returns 422 with `"No available provider found"` if none are available

**Tests**: 6 new model specs for provider availability logic + 2 integration specs for the auto-assignment endpoint. All 298 tests pass.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..855c07d 100644
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
+        provider = Provider.highest_rated_available(
+          scheduled_at: Time.zone.parse(params[:scheduled_at].to_s),
+          duration_minutes: params[:duration_minutes].to_i
+        )
+        return render_unprocessable(["No available provider found"]) unless provider
+      end
 
       result = Requests::CreateService.new(
         client: client,
diff --git a/affordance_request/app/models/provider.rb b/affordance_request/app/models/provider.rb
index 0f43919..9b599be 100644
--- a/affordance_request/app/models/provider.rb
+++ b/affordance_request/app/models/provider.rb
@@ -12,6 +12,21 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :available_at, ->(scheduled_at, duration_minutes) {
+    active.where.not(
+      id: Request.where(state: [:created, :created_accepted, :accepted, :started])
+        .where(
+          "scheduled_at < :end_time AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > :start_time",
+          start_time: scheduled_at,
+          end_time: scheduled_at + duration_minutes.minutes
+        )
+        .select(:provider_id)
+    )
+  }
+
+  def self.highest_rated_available(scheduled_at:, duration_minutes:)
+    available_at(scheduled_at, duration_minutes).order(rating: :desc).first
+  end
 
   private
 
diff --git a/affordance_request/spec/models/provider_spec.rb b/affordance_request/spec/models/provider_spec.rb
index ad86fbe..90f9ab2 100644
--- a/affordance_request/spec/models/provider_spec.rb
+++ b/affordance_request/spec/models/provider_spec.rb
@@ -59,6 +59,58 @@
     end
   end
 
+  describe ".highest_rated_available" do
+    let(:scheduled_at) { 3.days.from_now }
+    let(:duration) { 120 }
+
+    it "returns the highest-rated active provider" do
+      low_rated = create(:provider, rating: 3.0)
+      high_rated = create(:provider, rating: 5.0)
+
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to eq(high_rated)
+    end
+
+    it "excludes inactive providers" do
+      inactive = create(:provider, rating: 5.0, active: false)
+      active = create(:provider, rating: 3.0, active: true)
+
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to eq(active)
+    end
+
+    it "excludes providers with overlapping requests" do
+      busy_provider = create(:provider, rating: 5.0)
+      free_provider = create(:provider, rating: 3.0)
+
+      create(:request, provider: busy_provider, scheduled_at: scheduled_at, duration_minutes: duration, state: "accepted")
+
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to eq(free_provider)
+    end
+
+    it "allows providers whose requests don't overlap" do
+      provider = create(:provider, rating: 5.0)
+      create(:request, provider: provider, scheduled_at: scheduled_at - 3.hours, duration_minutes: 60, state: "accepted")
+
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to eq(provider)
+    end
+
+    it "ignores completed/canceled/declined requests" do
+      provider = create(:provider, rating: 5.0)
+      create(:request, :fulfilled, provider: provider, scheduled_at: scheduled_at, duration_minutes: duration)
+
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to eq(provider)
+    end
+
+    it "returns nil when no providers are available" do
+      result = Provider.highest_rated_available(scheduled_at: scheduled_at, duration_minutes: duration)
+      expect(result).to be_nil
+    end
+  end
+
   describe "notification_preferences" do
     it "has default notification preferences" do
       provider = create(:provider)
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..623f14f 100644
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
+      it "assigns the highest-rated available provider" do
+        create(:provider, rating: 3.0)
+        top_provider = create(:provider, rating: 5.0)
+
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(top_provider.id)
+      end
+
+      it "returns error when no providers are available" do
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+        body = JSON.parse(response.body)
+        expect(body["errors"]).to include("No available provider found")
+      end
+    end
   end
 
   describe "POST /api/requests/direct" do
```
