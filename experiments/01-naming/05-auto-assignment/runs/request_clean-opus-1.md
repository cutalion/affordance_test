# Experiment: 05-auto-assignment
# App: request_clean | Model: opus | Run: 1
# Branch: experiment/05-auto-assignment/request_clean/opus/run-1

---

## Claude Output

Done. Here's a summary of the changes:

**Migration**: Made `provider_id` nullable on the `requests` table.

**Provider model**: Added `highest_rated` scope and `available_at(scheduled_at, duration_minutes)` class method that finds active providers with no scheduling conflicts, ordered by rating descending.

**Request model**: Made `provider` association optional.

**CreateService**: When no provider is passed, calls `auto_assign_provider` which uses `Provider.available_at` to find the best match. Returns an error if no provider is available.

**Controller**: `provider_id` is now optional in `POST /api/requests`. If omitted, auto-assignment kicks in.

**Tests added** (9 new examples, 273 total passing):
- `Provider.available_at` — overlap exclusion, rating ordering, inactive exclusion
- `CreateService` without provider — assigns top-rated, skips busy, errors when none available
- API integration — auto-assigns highest-rated, returns 422 when none available

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..d98b8c3 100644
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
@@ -30,7 +33,9 @@ def create
       if result[:success]
         render json: request_detail_json(result[:request]), status: :created
       else
-        render_unprocessable(result[:errors].full_messages)
+        errors = result[:errors]
+        messages = errors.respond_to?(:full_messages) ? errors.full_messages : Array(errors)
+        render_unprocessable(messages)
       end
     end
 
diff --git a/affordance_request_clean/app/models/provider.rb b/affordance_request_clean/app/models/provider.rb
index 0f43919..ca26c43 100644
--- a/affordance_request_clean/app/models/provider.rb
+++ b/affordance_request_clean/app/models/provider.rb
@@ -12,6 +12,17 @@ class Provider < ApplicationRecord
   before_validation :generate_api_token, on: :create
 
   scope :active, -> { where(active: true) }
+  scope :highest_rated, -> { order(rating: :desc) }
+
+  def self.available_at(scheduled_at, duration_minutes)
+    ending_at = scheduled_at + duration_minutes.minutes
+    busy_provider_ids = Request
+      .where(state: %w[pending confirmed in_progress])
+      .where("scheduled_at < ? AND datetime(scheduled_at, '+' || duration_minutes || ' minutes') > ?", ending_at, scheduled_at)
+      .select(:provider_id)
+
+    active.where.not(id: busy_provider_ids).highest_rated
+  end
 
   private
 
diff --git a/affordance_request_clean/app/models/request.rb b/affordance_request_clean/app/models/request.rb
index 67cb0ca..3bbeca7 100644
--- a/affordance_request_clean/app/models/request.rb
+++ b/affordance_request_clean/app/models/request.rb
@@ -3,7 +3,7 @@ class Request < ApplicationRecord
   include Paginatable
 
   belongs_to :client
-  belongs_to :provider
+  belongs_to :provider, optional: true
   has_one :payment, dependent: :destroy
   has_many :reviews, dependent: :destroy
 
diff --git a/affordance_request_clean/app/services/requests/create_service.rb b/affordance_request_clean/app/services/requests/create_service.rb
index 0314a96..7e609b4 100644
--- a/affordance_request_clean/app/services/requests/create_service.rb
+++ b/affordance_request_clean/app/services/requests/create_service.rb
@@ -7,9 +7,12 @@ def initialize(client:, provider:, params:)
     end
 
     def call
+      provider = @provider || auto_assign_provider
+      return { success: false, errors: "No available provider found" } unless provider
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
@@ -37,6 +40,15 @@ def call
 
     private
 
+    def auto_assign_provider
+      return nil unless @params[:scheduled_at] && @params[:duration_minutes]
+
+      Provider.available_at(
+        Time.zone.parse(@params[:scheduled_at].to_s),
+        @params[:duration_minutes].to_i
+      ).first
+    end
+
     def calculate_fee(amount_cents)
       (amount_cents * 0.1).to_i
     end
diff --git a/affordance_request_clean/db/migrate/20260407220526_allow_null_provider_on_requests.rb b/affordance_request_clean/db/migrate/20260407220526_allow_null_provider_on_requests.rb
new file mode 100644
index 0000000..352b1a8
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260407220526_allow_null_provider_on_requests.rb
@@ -0,0 +1,5 @@
+class AllowNullProviderOnRequests < ActiveRecord::Migration[8.1]
+  def change
+    change_column_null :requests, :provider_id, true
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..2dafaba 100644
--- a/affordance_request_clean/db/schema.rb
+++ b/affordance_request_clean/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_220526) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -78,7 +78,10 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
-    t.integer "provider_id", null: false
+    t.datetime "original_scheduled_at"
+    t.datetime "proposed_scheduled_at"
+    t.datetime "proposed_time"
+    t.integer "provider_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
diff --git a/affordance_request_clean/spec/models/provider_spec.rb b/affordance_request_clean/spec/models/provider_spec.rb
index ad86fbe..cdab2f8 100644
--- a/affordance_request_clean/spec/models/provider_spec.rb
+++ b/affordance_request_clean/spec/models/provider_spec.rb
@@ -59,6 +59,38 @@
     end
   end
 
+  describe ".available_at" do
+    let(:scheduled_at) { 3.days.from_now }
+    let(:duration) { 120 }
+
+    let!(:free_provider) { create(:provider, rating: 4.0) }
+    let!(:busy_provider) { create(:provider, rating: 5.0) }
+
+    before do
+      create(:request, provider: busy_provider,
+        scheduled_at: scheduled_at, duration_minutes: 60,
+        amount_cents: 100, currency: "RUB")
+    end
+
+    it "excludes providers with overlapping requests" do
+      result = Provider.available_at(scheduled_at, duration)
+      expect(result).to include(free_provider)
+      expect(result).not_to include(busy_provider)
+    end
+
+    it "returns providers ordered by rating descending" do
+      another = create(:provider, rating: 5.0)
+      result = Provider.available_at(scheduled_at, duration)
+      expect(result.first).to eq(another)
+    end
+
+    it "excludes inactive providers" do
+      free_provider.update!(active: false)
+      result = Provider.available_at(scheduled_at, duration)
+      expect(result).not_to include(free_provider)
+    end
+  end
+
   describe "notification_preferences" do
     it "has default notification preferences" do
       provider = create(:provider)
diff --git a/affordance_request_clean/spec/models/request_spec.rb b/affordance_request_clean/spec/models/request_spec.rb
index 218bb0f..653e6b7 100644
--- a/affordance_request_clean/spec/models/request_spec.rb
+++ b/affordance_request_clean/spec/models/request_spec.rb
@@ -3,7 +3,7 @@
 RSpec.describe Request, type: :model do
   describe "associations" do
     it { is_expected.to belong_to(:client) }
-    it { is_expected.to belong_to(:provider) }
+    it { is_expected.to belong_to(:provider).optional }
     it { is_expected.to have_one(:payment).dependent(:destroy) }
     it { is_expected.to have_many(:reviews).dependent(:destroy) }
   end
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..daea6cc 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -91,6 +91,27 @@
       post "/api/requests", params: { provider_id: provider.id }, headers: auth_headers(client)
       expect(response).to have_http_status(:unprocessable_entity)
     end
+
+    context "without provider_id (auto-assignment)" do
+      let(:auto_params) { request_params.except(:provider_id) }
+
+      it "auto-assigns the highest-rated available provider" do
+        low_rated = create(:provider, rating: 2.0)
+        high_rated = create(:provider, rating: 5.0)
+
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:created)
+        body = JSON.parse(response.body)
+        expect(body["provider_id"]).to eq(high_rated.id)
+      end
+
+      it "returns error when no providers are available" do
+        provider # ensure the default provider exists
+        Provider.update_all(active: false)
+        post "/api/requests", params: auto_params, headers: auth_headers(client)
+        expect(response).to have_http_status(:unprocessable_entity)
+      end
+    end
   end
 
   describe "PATCH /api/requests/:id/confirm" do
diff --git a/affordance_request_clean/spec/services/requests/create_service_spec.rb b/affordance_request_clean/spec/services/requests/create_service_spec.rb
index 9e9fd30..826b4dc 100644
--- a/affordance_request_clean/spec/services/requests/create_service_spec.rb
+++ b/affordance_request_clean/spec/services/requests/create_service_spec.rb
@@ -37,6 +37,34 @@
       end
     end
 
+    context "without a provider (auto-assignment)" do
+      subject(:result) { described_class.new(client: client, provider: nil, params: valid_params).call }
+
+      let!(:top_provider) { create(:provider, rating: 5.0, active: true) }
+      let!(:mid_provider) { create(:provider, rating: 3.0, active: true) }
+      let!(:inactive_provider) { create(:provider, rating: 5.0, active: false) }
+
+      it "assigns the highest-rated active provider" do
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(top_provider)
+      end
+
+      it "skips providers busy at the scheduled time" do
+        create(:request, provider: top_provider,
+          scheduled_at: valid_params[:scheduled_at],
+          duration_minutes: 60, amount_cents: 100, currency: "RUB")
+
+        expect(result[:success]).to be true
+        expect(result[:request].provider).to eq(mid_provider)
+      end
+
+      it "returns error when no providers are available" do
+        Provider.update_all(active: false)
+        expect(result[:success]).to be false
+        expect(result[:errors]).to include("No available provider found")
+      end
+    end
+
     context "with invalid params" do
       let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
 
```
