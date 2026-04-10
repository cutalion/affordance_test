# Experiment: 05-auto-assignment
# App: request_clean | Model: sonnet | Run: 3
# Branch: experiment/05-auto-assignment/request_clean/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

**`app/controllers/api/requests_controller.rb`** — extracted a `resolve_provider` private method:
- If `provider_id` is present: look up that provider, return 404 if not found (existing behavior)
- If absent: find `Provider.active.order(rating: :desc).first`, return 422 if none available

**`spec/requests/api/requests_spec.rb`** — added 3 new cases under "without provider_id":
- Auto-assigns the highest-rated active provider
- Skips inactive providers even if they have higher ratings
- Returns 422 when no active providers exist

All 25 specs pass.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..e40c33f 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -18,8 +18,8 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
-      return render_not_found unless provider
+      provider = resolve_provider
+      return if performed?
 
       result = Requests::CreateService.new(
         client: client,
@@ -92,6 +92,18 @@ def reject
 
     private
 
+    def resolve_provider
+      if params[:provider_id].present?
+        provider = Provider.find_by(id: params[:provider_id])
+        render_not_found unless provider
+        provider
+      else
+        provider = Provider.active.order(rating: :desc).first
+        render_unprocessable(["No active providers available"]) unless provider
+        provider
+      end
+    end
+
     def set_request
       @request = Request.find_by(id: params[:id])
       render_not_found unless @request
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..f2a4da9 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -91,6 +91,49 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id" do
+      let(:base_params) do
+        {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "auto-assigns the highest-rated active provider" do
+        provider  # ensure outer let provider (rating 4.5) is persisted
+        create(:provider, rating: 3.0, active: true)
+        high_rated = create(:provider, rating: 4.8, active: true)
+
+        post "/api/requests", params: base_params, headers: auth_headers(client)
+
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "ignores inactive providers when auto-assigning" do
+        provider  # ensure outer let provider (rating 4.5, active) is persisted
+        create(:provider, rating: 5.0, active: false)
+
+        post "/api/requests", params: base_params, headers: auth_headers(client)
+
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(provider.id)
+      end
+
+      it "returns 422 when no active providers are available" do
+        provider  # ensure outer let provider is persisted before disabling all
+        Provider.update_all(active: false)
+
+        post "/api/requests", params: base_params, headers: auth_headers(client)
+
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "PATCH /api/requests/:id/confirm" do
```
