# Experiment: 05-auto-assignment
# App: request | Model: opus | Run: 3
# Branch: experiment/05-auto-assignment/request/opus/run-3

---

## Claude Output

Done. Here's what was implemented:

**Migration** — Made `provider_id` nullable on the `requests` table.

**`Providers::AutoAssignService`** — Finds the highest-rated active provider with no scheduling conflict at the requested time. Checks for time overlap against existing non-canceled/rejected/declined/missed requests.

**`Requests::CreateService`** — Now accepts `provider` as optional. When nil, calls `AutoAssignService` to find one. Returns an error if no available provider is found.

**Controller** — `POST /api/requests` no longer requires `provider_id`. If omitted, auto-assignment kicks in.

**Tests** — 7 new specs covering the auto-assign service (highest-rated selection, conflict handling, canceled requests, inactive providers, no providers) and integration through the create service and API endpoint. Full suite: 301 tests, 0 failures.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..e02a10f 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
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
diff --git a/affordance_request/app/models/request.rb b/affordance_request/app/models/request.rb
index 1c6cff4..84a662f 100644
--- a/affordance_request/app/models/request.rb
+++ b/affordance_request/app/models/request.rb
@@ -3,7 +3,7 @@ class Request < ApplicationRecord
   include Paginatable
 
   belongs_to :client
-  belongs_to :provider
+  belongs_to :provider, optional: true
   has_one :payment, dependent: :destroy
   has_many :reviews, dependent: :destroy
 
diff --git a/affordance_request/app/services/providers/auto_assign_service.rb b/affordance_request/app/services/providers/auto_assign_service.rb
new file mode 100644
index 0000000..1183064
--- /dev/null
+++ b/affordance_request/app/services/providers/auto_assign_service.rb
@@ -0,0 +1,28 @@
+module Providers
+  class AutoAssignService
+    def initialize(scheduled_at:, duration_minutes:)
+      @scheduled_at = scheduled_at
+      @duration_minutes = duration_minutes
+    end
+
+    def call
+      available_providers = Provider.active.order(rating: :desc)
+
+      available_providers.find do |provider|
+        !has_conflicting_request?(provider)
+      end
+    end
+
+    private
+
+    def has_conflicting_request?(provider)
+      request_end_time = @scheduled_at + @duration_minutes.to_i.minutes
+
+      provider.requests
+        .where.not(state: %w[canceled rejected declined missed])
+        .where("scheduled_at < ? AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > ?",
+          request_end_time, @scheduled_at)
+        .exists?
+    end
+  end
+end
diff --git a/affordance_request/app/services/requests/create_service.rb b/affordance_request/app/services/requests/create_service.rb
index 0314a96..16d49d0 100644
--- a/affordance_request/app/services/requests/create_service.rb
+++ b/affordance_request/app/services/requests/create_service.rb
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
+      provider = @provider || auto_assign_provider
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
@@ -40,5 +43,18 @@ def call
     def calculate_fee(amount_cents)
       (amount_cents * 0.1).to_i
     end
+
+    def auto_assign_provider
+      Providers::AutoAssignService.new(
+        scheduled_at: Time.zone.parse(@params[:scheduled_at].to_s),
+        duration_minutes: @params[:duration_minutes]
+      ).call
+    end
+
+    def no_provider_errors
+      errors = ActiveModel::Errors.new(Request.new)
+      errors.add(:provider, "no available provider found")
+      errors
+    end
   end
 end
diff --git a/affordance_request/db/migrate/20260407125319_change_provider_id_nullable_on_requests.rb b/affordance_request/db/migrate/20260407125319_change_provider_id_nullable_on_requests.rb
new file mode 100644
index 0000000..8a6e5b5
--- /dev/null
+++ b/affordance_request/db/migrate/20260407125319_change_provider_id_nullable_on_requests.rb
@@ -0,0 +1,5 @@
+class ChangeProviderIdNullableOnRequests < ActiveRecord::Migration[8.1]
+  def change
+    change_column_null :requests, :provider_id, true
+  end
+end
diff --git a/affordance_request/db/schema.rb b/affordance_request/db/schema.rb
index 18c568a..f5b12d2 100644
--- a/affordance_request/db/schema.rb
+++ b/affordance_request/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_125319) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -78,7 +78,9 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
-    t.integer "provider_id", null: false
+    t.text "propose_reason"
+    t.datetime "proposed_scheduled_at"
+    t.integer "provider_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
diff --git a/affordance_request/spec/models/request_spec.rb b/affordance_request/spec/models/request_spec.rb
index c3d38c1..a3b28fc 100644
--- a/affordance_request/spec/models/request_spec.rb
+++ b/affordance_request/spec/models/request_spec.rb
@@ -3,7 +3,7 @@
 RSpec.describe Request, type: :model do
   describe "associations" do
     it { is_expected.to belong_to(:client) }
-    it { is_expected.to belong_to(:provider) }
+    it { is_expected.to belong_to(:provider).optional }
     it { is_expected.to have_one(:payment).dependent(:destroy) }
     it { is_expected.to have_many(:reviews).dependent(:destroy) }
   end
diff --git a/affordance_request/spec/requests/api/requests_spec.rb b/affordance_request/spec/requests/api/requests_spec.rb
index 772331d..3f9f534 100644
--- a/affordance_request/spec/requests/api/requests_spec.rb
+++ b/affordance_request/spec/requests/api/requests_spec.rb
@@ -91,6 +91,30 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id (auto-assignment)" do
+      let!(:high_rated_provider) { create(:provider, rating: 5.0) }
+
+      it "auto-assigns the highest-rated available provider" do
+        params = request_params.except(:provider_id)
+        post "/api/requests", params: params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated_provider.id)
+      end
+
+      it "returns error when no providers are available" do
+        params = {
+          scheduled_at: 3.days.from_now.iso8601,
+          duration_minutes: 120,
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+        Provider.update_all(active: false)
+        post "/api/requests", params: params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "POST /api/requests/direct" do
diff --git a/affordance_request/spec/services/providers/auto_assign_service_spec.rb b/affordance_request/spec/services/providers/auto_assign_service_spec.rb
new file mode 100644
index 0000000..babc58d
--- /dev/null
+++ b/affordance_request/spec/services/providers/auto_assign_service_spec.rb
@@ -0,0 +1,81 @@
+require "rails_helper"
+
+RSpec.describe Providers::AutoAssignService do
+  let(:scheduled_at) { 3.days.from_now }
+  let(:duration_minutes) { 120 }
+
+  subject(:result) do
+    described_class.new(scheduled_at: scheduled_at, duration_minutes: duration_minutes).call
+  end
+
+  context "when there are active providers" do
+    let!(:low_rated) { create(:provider, rating: 3.0) }
+    let!(:high_rated) { create(:provider, rating: 5.0) }
+    let!(:mid_rated) { create(:provider, rating: 4.0) }
+
+    it "returns the highest-rated provider" do
+      expect(result).to eq(high_rated)
+    end
+
+    context "when the highest-rated provider has a conflicting request" do
+      before do
+        create(:request, provider: high_rated, scheduled_at: scheduled_at, duration_minutes: 60)
+      end
+
+      it "returns the next highest-rated available provider" do
+        expect(result).to eq(mid_rated)
+      end
+    end
+
+    context "when all providers have conflicting requests" do
+      before do
+        [high_rated, mid_rated, low_rated].each do |provider|
+          create(:request, provider: provider, scheduled_at: scheduled_at, duration_minutes: 60)
+        end
+      end
+
+      it "returns nil" do
+        expect(result).to be_nil
+      end
+    end
+  end
+
+  context "when a provider has a canceled request at that time" do
+    let!(:provider) { create(:provider, rating: 5.0) }
+
+    before do
+      create(:request, :canceled, provider: provider, scheduled_at: scheduled_at, duration_minutes: 60)
+    end
+
+    it "considers the provider available" do
+      expect(result).to eq(provider)
+    end
+  end
+
+  context "when a provider has a non-overlapping request" do
+    let!(:provider) { create(:provider, rating: 5.0) }
+
+    before do
+      create(:request, provider: provider, scheduled_at: scheduled_at + 3.hours, duration_minutes: 60)
+    end
+
+    it "considers the provider available" do
+      expect(result).to eq(provider)
+    end
+  end
+
+  context "when inactive providers exist" do
+    let!(:inactive_provider) { create(:provider, rating: 5.0, active: false) }
+    let!(:active_provider) { create(:provider, rating: 3.0) }
+
+    it "only considers active providers" do
+      expect(result).to eq(active_provider)
+    end
+  end
+
+  context "when no providers exist" do
+    it "returns nil" do
+      expect(result).to be_nil
+    end
+  end
+end
diff --git a/affordance_request/spec/services/requests/create_service_spec.rb b/affordance_request/spec/services/requests/create_service_spec.rb
index 9671082..29dc873 100644
--- a/affordance_request/spec/services/requests/create_service_spec.rb
+++ b/affordance_request/spec/services/requests/create_service_spec.rb
@@ -37,6 +37,27 @@
       end
     end
 
+    context "without a provider (auto-assignment)" do
+      subject(:result) { described_class.new(client: client, params: valid_params).call }
+
+      let!(:high_rated_provider) { create(:provider, rating: 5.0) }
+      let!(:low_rated_provider) { create(:provider, rating: 3.0) }
+
+      it "auto-assigns the highest-rated available provider" do
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(high_rated_provider)
+      end
+
+      context "when no providers are available" do
+        before { Provider.update_all(active: false) }
+
+        it "returns an error" do
+          expect(result[:success]).to be false
+          expect(result[:errors].full_messages).to include("Provider no available provider found")
+        end
+      end
+    end
+
     context "with invalid params" do
       let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
 
```
