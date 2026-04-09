# Experiment: e05-recurring-bookings
# App: app_bravo | Model: opus | Run: 2
# Branch: debt_experiment/e05-recurring-bookings/app_bravo/opus/run-2

---

## Claude Output

All done. Here's what was implemented:

**Migration** — `db/migrate/20260409192213_create_recurring_bookings.rb`
- `recurring_bookings` table with client, provider, scheduled_at, duration_minutes, sessions_count (default 5), location, notes
- Added `recurring_booking_id` foreign key to `requests`

**Model** — `app/models/recurring_booking.rb`
- `belongs_to :client`, `belongs_to :provider`, `has_many :requests`
- Validates presence of scheduled_at, duration_minutes, sessions_count

**Updated** `app/models/request.rb` — added `belongs_to :recurring_booking, optional: true`

**Service** — `app/services/requests/create_recurring_service.rb`
- Creates a `RecurringBooking` and 5 `Request` records scheduled 1 week apart (same day/time)
- All wrapped in a transaction — if any request fails, everything rolls back
- Sends `:recurring_booking_created` notification to the provider

**Endpoint** — `POST /api/requests/recurring`
- Accepts `provider_id`, `scheduled_at`, `duration_minutes`, `location`, `notes`
- Returns the recurring booking with its 5 request summaries

**Tests** — 18 new specs (model validations, associations, service behavior including scheduling logic, rollback on failure, and notifications). Full suite: 142 tests, 0 failures.

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/requests_controller.rb b/app_bravo/app/controllers/api/requests_controller.rb
index 9b6998d..16627b4 100644
--- a/app_bravo/app/controllers/api/requests_controller.rb
+++ b/app_bravo/app/controllers/api/requests_controller.rb
@@ -34,6 +34,26 @@ def create
       end
     end
 
+    def recurring
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
+        render json: recurring_booking_json(result[:recurring_booking], result[:requests]), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def accept
       provider = current_provider!
       return if performed?
@@ -95,6 +115,22 @@ def request_summary_json(request)
       }
     end
 
+    def recurring_booking_json(recurring_booking, requests)
+      {
+        id: recurring_booking.id,
+        sessions_count: recurring_booking.sessions_count,
+        scheduled_at: recurring_booking.scheduled_at,
+        duration_minutes: recurring_booking.duration_minutes,
+        location: recurring_booking.location,
+        notes: recurring_booking.notes,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        requests: requests.map { |r| request_summary_json(r) },
+        created_at: recurring_booking.created_at,
+        updated_at: recurring_booking.updated_at
+      }
+    end
+
     def request_detail_json(request)
       {
         id: request.id,
diff --git a/app_bravo/app/models/recurring_booking.rb b/app_bravo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..daa8220
--- /dev/null
+++ b/app_bravo/app/models/recurring_booking.rb
@@ -0,0 +1,9 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :scheduled_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :sessions_count, presence: true, numericality: { greater_than: 0 }
+end
diff --git a/app_bravo/app/models/request.rb b/app_bravo/app/models/request.rb
index 7f12baf..1e39fc2 100644
--- a/app_bravo/app/models/request.rb
+++ b/app_bravo/app/models/request.rb
@@ -4,6 +4,7 @@ class Request < ApplicationRecord
 
   belongs_to :client
   belongs_to :provider
+  belongs_to :recurring_booking, optional: true
   has_one :order, dependent: :destroy
 
   validates :scheduled_at, presence: true
diff --git a/app_bravo/app/services/requests/create_recurring_service.rb b/app_bravo/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..feafa08
--- /dev/null
+++ b/app_bravo/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,48 @@
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
+      RecurringBooking.transaction do
+        recurring_booking = RecurringBooking.create!(
+          client: @client,
+          provider: @provider,
+          scheduled_at: @params[:scheduled_at],
+          duration_minutes: @params[:duration_minutes],
+          location: @params[:location],
+          notes: @params[:notes],
+          sessions_count: SESSIONS_COUNT
+        )
+
+        requests = SESSIONS_COUNT.times.map do |i|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: Time.parse(@params[:scheduled_at].to_s) + i.weeks,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes]
+          )
+        end
+
+        NotificationService.notify(
+          @provider,
+          :recurring_booking_created,
+          recurring_booking_id: recurring_booking.id,
+          sessions_count: SESSIONS_COUNT
+        )
+
+        { success: true, recurring_booking: recurring_booking, requests: requests }
+      end
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/app_bravo/config/routes.rb b/app_bravo/config/routes.rb
index 8d32af9..9d553ce 100644
--- a/app_bravo/config/routes.rb
+++ b/app_bravo/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :recurring
+      end
       member do
         patch :accept
         patch :decline
diff --git a/app_bravo/db/migrate/20260409192213_create_recurring_bookings.rb b/app_bravo/db/migrate/20260409192213_create_recurring_bookings.rb
new file mode 100644
index 0000000..9734c23
--- /dev/null
+++ b/app_bravo/db/migrate/20260409192213_create_recurring_bookings.rb
@@ -0,0 +1,17 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.datetime :scheduled_at, null: false
+      t.integer :duration_minutes, null: false
+      t.integer :sessions_count, null: false, default: 5
+      t.string :location
+      t.text :notes
+
+      t.timestamps
+    end
+
+    add_reference :requests, :recurring_booking, null: true, foreign_key: true
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index 667709c..8aee255 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_075820) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_192213) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
diff --git a/app_bravo/spec/factories/recurring_bookings.rb b/app_bravo/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..35d9beb
--- /dev/null
+++ b/app_bravo/spec/factories/recurring_bookings.rb
@@ -0,0 +1,11 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    scheduled_at { 3.days.from_now }
+    duration_minutes { 120 }
+    sessions_count { 5 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+  end
+end
diff --git a/app_bravo/spec/models/recurring_booking_spec.rb b/app_bravo/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..2173195
--- /dev/null
+++ b/app_bravo/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,49 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking do
+  describe "validations" do
+    it "is valid with valid attributes" do
+      recurring_booking = build(:recurring_booking)
+      expect(recurring_booking).to be_valid
+    end
+
+    it "requires scheduled_at" do
+      recurring_booking = build(:recurring_booking, scheduled_at: nil)
+      expect(recurring_booking).not_to be_valid
+    end
+
+    it "requires duration_minutes" do
+      recurring_booking = build(:recurring_booking, duration_minutes: nil)
+      expect(recurring_booking).not_to be_valid
+    end
+
+    it "requires duration_minutes to be positive" do
+      recurring_booking = build(:recurring_booking, duration_minutes: 0)
+      expect(recurring_booking).not_to be_valid
+    end
+
+    it "requires sessions_count" do
+      recurring_booking = build(:recurring_booking, sessions_count: nil)
+      expect(recurring_booking).not_to be_valid
+    end
+  end
+
+  describe "associations" do
+    it "has many requests" do
+      recurring_booking = create(:recurring_booking)
+      request = create(:request, recurring_booking: recurring_booking,
+                                 client: recurring_booking.client,
+                                 provider: recurring_booking.provider)
+      expect(recurring_booking.requests).to include(request)
+    end
+
+    it "nullifies requests on destroy" do
+      recurring_booking = create(:recurring_booking)
+      request = create(:request, recurring_booking: recurring_booking,
+                                 client: recurring_booking.client,
+                                 provider: recurring_booking.provider)
+      recurring_booking.destroy
+      expect(request.reload.recurring_booking_id).to be_nil
+    end
+  end
+end
diff --git a/app_bravo/spec/services/requests/create_recurring_service_spec.rb b/app_bravo/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..c7092fd
--- /dev/null
+++ b/app_bravo/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,84 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now.beginning_of_hour }
+  let(:valid_params) do
+    {
+      scheduled_at: scheduled_at,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session"
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
+      it "sets sessions_count to 5" do
+        expect(result[:recurring_booking].sessions_count).to eq(5)
+      end
+
+      it "links all requests to the recurring booking" do
+        requests = result[:requests]
+        recurring_booking = result[:recurring_booking]
+        expect(requests).to all(have_attributes(recurring_booking_id: recurring_booking.id))
+      end
+
+      it "schedules requests one week apart" do
+        requests = result[:requests]
+        5.times do |i|
+          expected_time = scheduled_at + i.weeks
+          expect(requests[i].scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "copies duration, location, and notes to each request" do
+        requests = result[:requests]
+        requests.each do |request|
+          expect(request.duration_minutes).to eq(120)
+          expect(request.location).to eq("123 Main St")
+          expect(request.notes).to eq("Weekly session")
+        end
+      end
+
+      it "creates all requests in pending state" do
+        requests = result[:requests]
+        expect(requests).to all(have_attributes(state: "pending"))
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=recurring_booking_created")
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil } }
+
+      it "returns failure" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "does not create any records" do
+        expect { result }.not_to change(RecurringBooking, :count)
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+  end
+end
```
