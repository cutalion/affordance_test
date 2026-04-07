# Experiment: 05-auto-assignment
# App: order | Model: sonnet | Run: 3
# Branch: experiment/05-auto-assignment/order/sonnet/run-3

---

## Claude Output

Done. Here's what was implemented:

- **`app/services/providers/auto_assign_service.rb`** — queries `Provider.active.order(rating: :desc).first` to find the best available provider
- **`app/controllers/api/orders_controller.rb`** — `provider_id` is now optional; if absent, delegates to `AutoAssignService`; returns 404 if no active providers exist
- **Specs** — unit tests for the service (highest-rated wins, inactive excluded, nil when none available) and request specs for the auto-assignment flow

---

## Git Diff

```diff
diff --git a/affordance_order/app/controllers/api/orders_controller.rb b/affordance_order/app/controllers/api/orders_controller.rb
index 2418afc..9a8dc04 100644
--- a/affordance_order/app/controllers/api/orders_controller.rb
+++ b/affordance_order/app/controllers/api/orders_controller.rb
@@ -18,7 +18,11 @@ def create
       client = current_client!
       return if performed?
 
-      provider = Provider.find_by(id: params[:provider_id])
+      provider = if params[:provider_id].present?
+        Provider.find_by(id: params[:provider_id])
+      else
+        Providers::AutoAssignService.new.call
+      end
       return render_not_found unless provider
 
       result = Orders::CreateService.new(
diff --git a/affordance_order/app/services/providers/auto_assign_service.rb b/affordance_order/app/services/providers/auto_assign_service.rb
new file mode 100644
index 0000000..cc3f10e
--- /dev/null
+++ b/affordance_order/app/services/providers/auto_assign_service.rb
@@ -0,0 +1,7 @@
+module Providers
+  class AutoAssignService
+    def call
+      Provider.active.order(rating: :desc).first
+    end
+  end
+end
diff --git a/affordance_order/spec/requests/api/orders_spec.rb b/affordance_order/spec/requests/api/orders_spec.rb
index b5e1bbb..69fc70f 100644
--- a/affordance_order/spec/requests/api/orders_spec.rb
+++ b/affordance_order/spec/requests/api/orders_spec.rb
@@ -91,6 +91,30 @@
       post "/api/orders", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id" do
+      let(:params_without_provider) do
+        order_params.except(:provider_id)
+      end
+
+      it "auto-assigns the highest-rated active provider" do
+        high_rated = create(:provider, rating: 5.0)
+
+        post "/api/orders", params: params_without_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "returns 404 when no active providers exist" do
+        # Force lazy `provider` to be created before deactivating all providers
+        params_without_provider
+        Provider.update_all(active: false)
+
+        post "/api/orders", params: params_without_provider, headers: auth_headers(client)
+        expect(response).to have_http_status(:not_found)
+      end
+    end
   end
 
   describe "PATCH /api/orders/:id/confirm" do
diff --git a/affordance_order/spec/services/providers/auto_assign_service_spec.rb b/affordance_order/spec/services/providers/auto_assign_service_spec.rb
new file mode 100644
index 0000000..5a34ede
--- /dev/null
+++ b/affordance_order/spec/services/providers/auto_assign_service_spec.rb
@@ -0,0 +1,34 @@
+require "rails_helper"
+
+RSpec.describe Providers::AutoAssignService do
+  subject(:result) { described_class.new.call }
+
+  describe "#call" do
+    context "when active providers exist" do
+      let!(:lower_rated) { create(:provider, rating: 3.5) }
+      let!(:highest_rated) { create(:provider, rating: 5.0) }
+      let!(:mid_rated) { create(:provider, rating: 4.0) }
+
+      it "returns the highest-rated active provider" do
+        expect(result).to eq(highest_rated)
+      end
+    end
+
+    context "when some providers are inactive" do
+      let!(:inactive) { create(:provider, rating: 5.0, active: false) }
+      let!(:active) { create(:provider, rating: 3.0, active: true) }
+
+      it "only considers active providers" do
+        expect(result).to eq(active)
+      end
+    end
+
+    context "when no active providers exist" do
+      before { create(:provider, rating: 5.0, active: false) }
+
+      it "returns nil" do
+        expect(result).to be_nil
+      end
+    end
+  end
+end
```
