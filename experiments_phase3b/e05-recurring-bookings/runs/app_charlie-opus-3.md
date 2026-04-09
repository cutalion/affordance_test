# Experiment: e05-recurring-bookings
# App: app_charlie | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_charlie/opus/run-3

---

## Claude Output

All 121 specs pass. Here's what was implemented:

**Recurring Weekly Bookings** — creates 5 sessions with the same provider at the same time, each one week apart.

### Changes:

1. **Migration** (`db/migrate/..._add_recurring_fields_to_requests.rb`) — adds `recurring_group_id` (string, indexed) and `recurring_index` (integer) to requests

2. **Request model** — added:
   - `recurring` and `by_recurring_group` scopes
   - `recurring?` predicate method
   - `recurring_siblings` method to find other requests in the same group

3. **`Requests::CreateRecurringService`** — creates 5 requests in a transaction, each scheduled 1 week apart, sharing a UUID `recurring_group_id` with indexes 1-5. Notifies the provider once for the whole group.

4. **API endpoint** — `POST /api/requests/recurring` (same params as single create). Returns all 5 requests and the `recurring_group_id`.

5. **Specs** — model specs for `recurring?` and `recurring_siblings`, service specs covering happy path (5 requests created, weekly spacing, shared group ID, notification), validation errors (transaction rollback), and missing `scheduled_at`.

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..3712718 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -34,6 +34,31 @@ def create
       end
     end
 
+    def create_recurring
+      client = current_client!
+      return if performed?
+
+      provider = Provider.find_by(id: params[:provider_id])
+      return render_not_found unless provider
+
+      result = Requests::CreateRecurringService.new(
+        client: client,
+        provider: provider,
+        params: request_params
+      ).call
+
+      if result[:success]
+        render json: {
+          recurring_group_id: result[:recurring_group_id],
+          requests: result[:requests].map { |r| request_detail_json(r) }
+        }, status: :created
+      elsif result[:errors]
+        render_unprocessable(result[:errors].full_messages)
+      else
+        render json: { error: result[:error] }, status: :unprocessable_entity
+      end
+    end
+
     def accept
       provider = current_provider!
       return if performed?
@@ -162,6 +187,8 @@ def request_detail_json(request)
         expired_at: request.expired_at,
         started_at: request.started_at,
         completed_at: request.completed_at,
+        recurring_group_id: request.recurring_group_id,
+        recurring_index: request.recurring_index,
         client_id: request.client_id,
         provider_id: request.provider_id,
         payment: request.payment ? {
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..2ff144a 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -27,6 +27,17 @@ class Request < ApplicationRecord
     scope
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
+  scope :recurring, -> { where.not(recurring_group_id: nil) }
+  scope :by_recurring_group, ->(group_id) { where(recurring_group_id: group_id) if group_id.present? }
+
+  def recurring?
+    recurring_group_id.present?
+  end
+
+  def recurring_siblings
+    return Request.none unless recurring?
+    Request.where(recurring_group_id: recurring_group_id).where.not(id: id)
+  end
 
   aasm column: :state do
     state :pending, initial: true
diff --git a/app_charlie/app/services/requests/create_recurring_service.rb b/app_charlie/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..07dcdd5
--- /dev/null
+++ b/app_charlie/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,51 @@
+module Requests
+  class CreateRecurringService
+    SESSIONS_COUNT = 5
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      scheduled_at = Time.zone.parse(@params[:scheduled_at].to_s)
+      return { success: false, error: "scheduled_at is required" } unless scheduled_at
+
+      group_id = SecureRandom.uuid
+      requests = []
+
+      ActiveRecord::Base.transaction do
+        SESSIONS_COUNT.times do |i|
+          request = Request.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: scheduled_at + i.weeks,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB",
+            recurring_group_id: group_id,
+            recurring_index: i + 1
+          )
+          requests << request
+        end
+      end
+
+      NotificationService.notify(
+        @provider,
+        :recurring_booking_created,
+        recurring_group_id: group_id,
+        sessions_count: SESSIONS_COUNT,
+        first_request_id: requests.first.id
+      )
+
+      { success: true, requests: requests, recurring_group_id: group_id }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    rescue ArgumentError
+      { success: false, error: "Invalid scheduled_at format" }
+    end
+  end
+end
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..0da5115 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :recurring, action: :create_recurring
+      end
       member do
         patch :accept
         patch :decline
diff --git a/app_charlie/db/migrate/20260409193457_add_recurring_fields_to_requests.rb b/app_charlie/db/migrate/20260409193457_add_recurring_fields_to_requests.rb
new file mode 100644
index 0000000..55b7ab3
--- /dev/null
+++ b/app_charlie/db/migrate/20260409193457_add_recurring_fields_to_requests.rb
@@ -0,0 +1,13 @@
+class AddRecurringFieldsToRequests < ActiveRecord::Migration[8.1]
+  def change
+    unless column_exists?(:requests, :recurring_group_id)
+      add_column :requests, :recurring_group_id, :string
+    end
+    unless column_exists?(:requests, :recurring_index)
+      add_column :requests, :recurring_index, :integer
+    end
+    unless index_exists?(:requests, :recurring_group_id)
+      add_index :requests, :recurring_group_id
+    end
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 4757a0b..0a39cad 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_081113) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_193457) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -38,6 +38,7 @@
 
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "card_id"
     t.datetime "charged_at"
     t.datetime "created_at", null: false
@@ -68,10 +69,27 @@
     t.index ["email"], name: "index_providers_on_email", unique: true
   end
 
+  create_table "recurring_bookings", force: :cascade do |t|
+    t.integer "amount_cents", null: false
+    t.integer "client_id", null: false
+    t.datetime "created_at", null: false
+    t.string "currency", default: "RUB", null: false
+    t.integer "duration_minutes", null: false
+    t.string "location"
+    t.text "notes"
+    t.integer "provider_id", null: false
+    t.integer "sessions_count", default: 5, null: false
+    t.datetime "starts_at", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "amount_cents", null: false
     t.text "cancel_reason"
+    t.integer "cancellation_fee_cents", default: 0, null: false
     t.integer "client_id", null: false
     t.datetime "completed_at"
     t.datetime "created_at", null: false
@@ -81,7 +99,10 @@
     t.datetime "expired_at"
     t.string "location"
     t.text "notes"
+    t.text "proposal_note"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
+    t.integer "recurring_booking_id"
     t.string "recurring_group_id"
     t.integer "recurring_index"
     t.text "reject_reason"
@@ -91,6 +112,7 @@
     t.datetime "updated_at", null: false
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_booking_id"], name: "index_requests_on_recurring_booking_id"
     t.index ["recurring_group_id"], name: "index_requests_on_recurring_group_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
@@ -112,7 +134,10 @@
   add_foreign_key "cards", "clients"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "requests"
+  add_foreign_key "recurring_bookings", "clients"
+  add_foreign_key "recurring_bookings", "providers"
   add_foreign_key "requests", "clients"
   add_foreign_key "requests", "providers"
+  add_foreign_key "requests", "recurring_bookings"
   add_foreign_key "reviews", "requests"
 end
diff --git a/app_charlie/spec/factories/requests.rb b/app_charlie/spec/factories/requests.rb
index dad8264..595ef7e 100644
--- a/app_charlie/spec/factories/requests.rb
+++ b/app_charlie/spec/factories/requests.rb
@@ -47,6 +47,11 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :recurring do
+      recurring_group_id { SecureRandom.uuid }
+      sequence(:recurring_index) { |n| n }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_charlie/spec/models/request_spec.rb b/app_charlie/spec/models/request_spec.rb
index a9aece5..f23c750 100644
--- a/app_charlie/spec/models/request_spec.rb
+++ b/app_charlie/spec/models/request_spec.rb
@@ -182,6 +182,34 @@
     end
   end
 
+  describe "#recurring?" do
+    it "returns true when recurring_group_id is present" do
+      request = build(:request, recurring_group_id: "abc-123", recurring_index: 1)
+      expect(request).to be_recurring
+    end
+
+    it "returns false when recurring_group_id is nil" do
+      request = build(:request, recurring_group_id: nil)
+      expect(request).not_to be_recurring
+    end
+  end
+
+  describe "#recurring_siblings" do
+    it "returns other requests in the same recurring group" do
+      group_id = SecureRandom.uuid
+      r1 = create(:request, recurring_group_id: group_id, recurring_index: 1)
+      r2 = create(:request, recurring_group_id: group_id, recurring_index: 2, client: r1.client, provider: r1.provider)
+      r3 = create(:request, recurring_group_id: group_id, recurring_index: 3, client: r1.client, provider: r1.provider)
+
+      expect(r1.recurring_siblings).to match_array([r2, r3])
+    end
+
+    it "returns none for non-recurring requests" do
+      request = create(:request)
+      expect(request.recurring_siblings).to be_empty
+    end
+  end
+
   describe "scopes" do
     let!(:future_request) { create(:request, scheduled_at: 1.day.from_now) }
     let!(:past_request) { create(:request, scheduled_at: 1.day.ago) }
diff --git a/app_charlie/spec/services/requests/create_recurring_service_spec.rb b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..53d7f4a
--- /dev/null
+++ b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,90 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now.beginning_of_hour }
+  let(:valid_params) do
+    {
+      scheduled_at: scheduled_at.iso8601,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 350_000,
+      currency: "RUB"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: valid_params).call }
+
+  describe "#call" do
+    context "with valid params" do
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+
+      it "returns success with all requests" do
+        expect(result[:success]).to be true
+        expect(result[:requests].size).to eq(5)
+        expect(result[:recurring_group_id]).to be_present
+      end
+
+      it "assigns the same recurring_group_id to all requests" do
+        group_id = result[:recurring_group_id]
+        expect(result[:requests]).to all(have_attributes(recurring_group_id: group_id))
+      end
+
+      it "sets recurring_index from 1 to 5" do
+        indexes = result[:requests].map(&:recurring_index)
+        expect(indexes).to eq([1, 2, 3, 4, 5])
+      end
+
+      it "schedules each request one week apart" do
+        times = result[:requests].map(&:scheduled_at)
+        times.each_cons(2) do |earlier, later|
+          expect(later - earlier).to eq(1.week)
+        end
+      end
+
+      it "uses the same provider, client, and amount for all requests" do
+        result[:requests].each do |request|
+          expect(request.client).to eq(client)
+          expect(request.provider).to eq(provider)
+          expect(request.amount_cents).to eq(350_000)
+          expect(request.duration_minutes).to eq(120)
+        end
+      end
+
+      it "creates all requests in pending state" do
+        expect(result[:requests]).to all(have_attributes(state: "pending"))
+      end
+
+      it "notifies the provider about recurring booking" do
+        result
+        expect(read_notification_log).to include("event=recurring_booking_created")
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: scheduled_at.iso8601, duration_minutes: nil, amount_cents: nil } }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "does not create any requests (transaction rollback)" do
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+
+    context "with missing scheduled_at" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: 120, amount_cents: 350_000 } }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:error]).to eq("scheduled_at is required")
+      end
+    end
+  end
+end
```
