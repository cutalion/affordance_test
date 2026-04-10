# Experiment: e05-recurring-bookings
# App: app_charlie | Model: opus | Run: 2
# Branch: debt_experiment/e05-recurring-bookings/app_charlie/opus/run-2

---

## Claude Output

All 123 tests pass (17 new + 106 existing). Here's what was implemented:

## Summary

**Recurring weekly bookings** — a client can create 5 weekly sessions with the same provider in a single API call.

### Changes made:

1. **Migration** (`db/migrate/20260410082953_create_recurring_bookings.rb`) — new `recurring_bookings` table with `client_id`/`provider_id` FKs, plus `recurring_booking_id` FK added to `requests`

2. **RecurringBooking model** (`app/models/recurring_booking.rb`) — groups 5 requests together, `has_many :requests`

3. **Request model** (`app/models/request.rb`) — added `belongs_to :recurring_booking, optional: true`

4. **CreateRecurringService** (`app/services/requests/create_recurring_service.rb`) — creates all 5 requests in a transaction, each scheduled 1 week apart. Rolls back everything if any request fails validation. Notifies provider once.

5. **API endpoint** — `POST /api/requests/recurring` with the same params as regular booking creation. Returns `recurring_booking_id` and all 5 request details.

6. **Routes** (`config/routes.rb`) — added `post "requests/recurring"`

7. **JSON response** — `recurring_booking_id` now included in request detail JSON

8. **Tests** — 17 new specs covering the model associations, service happy path (5 requests created, weekly scheduling, state, linking), error rollback, and notifications.

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..79c7ec5 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -34,6 +34,29 @@ def create
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
+          recurring_booking_id: result[:recurring_booking].id,
+          requests: result[:requests].map { |r| request_detail_json(r) }
+        }, status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def accept
       provider = current_provider!
       return if performed?
@@ -164,6 +187,7 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_booking_id: request.recurring_booking_id,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
diff --git a/app_charlie/app/models/recurring_booking.rb b/app_charlie/app/models/recurring_booking.rb
new file mode 100644
index 0000000..17d9d72
--- /dev/null
+++ b/app_charlie/app/models/recurring_booking.rb
@@ -0,0 +1,5 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+end
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..f81a22c 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -4,6 +4,7 @@ class Request < ApplicationRecord
 
   belongs_to :client
   belongs_to :provider
+  belongs_to :recurring_booking, optional: true
   has_one :payment, dependent: :destroy
   has_many :reviews, dependent: :destroy
 
diff --git a/app_charlie/app/services/requests/create_recurring_service.rb b/app_charlie/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..1480552
--- /dev/null
+++ b/app_charlie/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,46 @@
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
+      ActiveRecord::Base.transaction do
+        recurring_booking = RecurringBooking.create!(
+          client: @client,
+          provider: @provider
+        )
+
+        requests = SESSIONS_COUNT.times.map do |week_offset|
+          scheduled_at = @params[:scheduled_at] && @params[:scheduled_at] + week_offset.weeks
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: scheduled_at,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB"
+          )
+        end
+
+        NotificationService.notify(
+          @provider,
+          :recurring_booking_created,
+          recurring_booking_id: recurring_booking.id,
+          request_ids: requests.map(&:id)
+        )
+
+        { success: true, recurring_booking: recurring_booking, requests: requests }
+      end
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..811f10f 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -10,6 +10,7 @@
       patch :default, on: :member, action: :set_default
     end
 
+    post "requests/recurring", to: "requests#create_recurring"
     resources :requests, only: [:index, :show, :create] do
       member do
         patch :accept
diff --git a/app_charlie/db/migrate/20260410082953_create_recurring_bookings.rb b/app_charlie/db/migrate/20260410082953_create_recurring_bookings.rb
new file mode 100644
index 0000000..aae030d
--- /dev/null
+++ b/app_charlie/db/migrate/20260410082953_create_recurring_bookings.rb
@@ -0,0 +1,16 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.integer :client_id, null: false
+      t.integer :provider_id, null: false
+
+      t.timestamps
+    end
+    add_index :recurring_bookings, :client_id
+    add_index :recurring_bookings, :provider_id
+    add_foreign_key :recurring_bookings, :clients
+    add_foreign_key :recurring_bookings, :providers
+
+    add_reference :requests, :recurring_booking, foreign_key: true, null: true
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..e52ebb1 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140805) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_082953) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -68,6 +68,15 @@
     t.index ["email"], name: "index_providers_on_email", unique: true
   end
 
+  create_table "recurring_bookings", force: :cascade do |t|
+    t.integer "client_id", null: false
+    t.datetime "created_at", null: false
+    t.integer "provider_id", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "amount_cents", null: false
@@ -82,6 +91,7 @@
     t.string "location"
     t.text "notes"
     t.integer "provider_id", null: false
+    t.integer "recurring_booking_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
@@ -89,6 +99,7 @@
     t.datetime "updated_at", null: false
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_booking_id"], name: "index_requests_on_recurring_booking_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
   end
@@ -109,7 +120,10 @@
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
diff --git a/app_charlie/docs/superpowers/specs/2026-04-10-recurring-bookings-design.md b/app_charlie/docs/superpowers/specs/2026-04-10-recurring-bookings-design.md
new file mode 100644
index 0000000..0092064
--- /dev/null
+++ b/app_charlie/docs/superpowers/specs/2026-04-10-recurring-bookings-design.md
@@ -0,0 +1,67 @@
+# Recurring Weekly Bookings
+
+## Summary
+
+Add the ability to create recurring weekly bookings — 5 sessions with the same provider at the same time. A single API call creates 5 individual `Request` records, each scheduled one week apart, grouped under a `RecurringBooking` record.
+
+## Design
+
+### New Model: `RecurringBooking`
+
+Groups 5 weekly requests together.
+
+| Column | Type | Notes |
+|--------|------|-------|
+| id | integer | PK |
+| client_id | integer | FK to clients |
+| provider_id | integer | FK to providers |
+| created_at | datetime | |
+| updated_at | datetime | |
+
+**Associations**:
+- `belongs_to :client`
+- `belongs_to :provider`
+- `has_many :requests`
+
+### Changes to `Request`
+
+- Add `recurring_booking_id` (integer, nullable FK to `recurring_bookings`)
+- Add `belongs_to :recurring_booking, optional: true`
+
+### New Service: `Requests::CreateRecurringService`
+
+**Input**: `client`, `provider`, `params` (same as CreateService: `scheduled_at`, `duration_minutes`, `location`, `notes`, `amount_cents`, `currency`)
+
+**Behavior**:
+1. Wrap everything in a transaction
+2. Create a `RecurringBooking` record
+3. Create 5 `Request` records with `scheduled_at` offset by 0, 1, 2, 3, 4 weeks
+4. Notify provider once about the recurring booking
+5. Return `{ success: true, recurring_booking: rb, requests: [...] }`
+
+**Error handling**: If any request fails validation, roll back the entire transaction.
+
+### New API Endpoint
+
+`POST /api/requests/recurring`
+
+**Request body**: Same params as `POST /api/requests` plus `provider_id`.
+
+**Response** (201):
+```json
+{
+  "recurring_booking_id": 1,
+  "requests": [
+    { /* standard request detail JSON */ },
+    ...
+  ]
+}
+```
+
+### Key Assumptions
+
+- Each of the 5 requests is independent for state management (accept/decline/cancel individually)
+- The `scheduled_at` param is the time of the first session; subsequent sessions are exactly 7 days apart
+- Amount, location, duration, notes are identical across all 5 sessions
+- Provider receives one notification for the series creation
+- No special handling for canceling the entire series (cancel individually)
diff --git a/app_charlie/spec/factories/recurring_bookings.rb b/app_charlie/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..4b9cc77
--- /dev/null
+++ b/app_charlie/spec/factories/recurring_bookings.rb
@@ -0,0 +1,6 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+  end
+end
diff --git a/app_charlie/spec/models/recurring_booking_spec.rb b/app_charlie/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..ed553e2
--- /dev/null
+++ b/app_charlie/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,9 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking, type: :model do
+  describe "associations" do
+    it { is_expected.to belong_to(:client) }
+    it { is_expected.to belong_to(:provider) }
+    it { is_expected.to have_many(:requests).dependent(:nullify) }
+  end
+end
diff --git a/app_charlie/spec/services/requests/create_recurring_service_spec.rb b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..600cffd
--- /dev/null
+++ b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,118 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:first_scheduled_at) { 3.days.from_now }
+  let(:valid_params) do
+    {
+      scheduled_at: first_scheduled_at,
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
+      it "returns success" do
+        expect(result[:success]).to be true
+      end
+
+      it "creates a recurring booking" do
+        expect { result }.to change(RecurringBooking, :count).by(1)
+      end
+
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+
+      it "schedules requests one week apart" do
+        requests = result[:requests].sort_by(&:scheduled_at)
+        requests.each_with_index do |request, i|
+          expected_time = first_scheduled_at + i.weeks
+          expect(request.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "creates all requests in pending state" do
+        result[:requests].each do |request|
+          expect(request.state).to eq("pending")
+        end
+      end
+
+      it "links all requests to the recurring booking" do
+        recurring_booking = result[:recurring_booking]
+        result[:requests].each do |request|
+          expect(request.recurring_booking).to eq(recurring_booking)
+        end
+      end
+
+      it "sets the same provider and client on all requests" do
+        result[:requests].each do |request|
+          expect(request.client).to eq(client)
+          expect(request.provider).to eq(provider)
+        end
+      end
+
+      it "copies amount, location, duration, and notes to all requests" do
+        result[:requests].each do |request|
+          expect(request.amount_cents).to eq(350_000)
+          expect(request.currency).to eq("RUB")
+          expect(request.duration_minutes).to eq(120)
+          expect(request.location).to eq("123 Main St")
+          expect(request.notes).to eq("Weekly session")
+        end
+      end
+
+      it "notifies the provider about the recurring booking" do
+        result
+        log = read_notification_log
+        expect(log).to include("event=recurring_booking_created")
+      end
+
+      it "returns the recurring booking" do
+        expect(result[:recurring_booking]).to be_a(RecurringBooking)
+        expect(result[:recurring_booking]).to be_persisted
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil } }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "does not create any requests" do
+        expect { result }.not_to change(Request, :count)
+      end
+
+      it "does not create a recurring booking" do
+        expect { result }.not_to change(RecurringBooking, :count)
+      end
+    end
+
+    context "with default currency" do
+      let(:valid_params) do
+        {
+          scheduled_at: first_scheduled_at,
+          duration_minutes: 60,
+          location: "456 Oak Ave",
+          amount_cents: 100_000
+        }
+      end
+
+      it "defaults currency to RUB" do
+        result[:requests].each do |request|
+          expect(request.currency).to eq("RUB")
+        end
+      end
+    end
+  end
+end
```
