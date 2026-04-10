# Experiment: e05-recurring-bookings
# App: app_bravo | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_bravo/opus/run-3

---

## Claude Output

All 133 tests pass. Here's what was implemented:

**Recurring Weekly Bookings** — a client can create a recurring booking that generates 5 weekly requests with the same provider, at the same time each week.

### Changes made:

1. **Migration** (`db/migrate/20260408140807_create_recurring_bookings.rb`) — Creates the `recurring_bookings` table and adds `recurring_booking_id` foreign key to `requests`.

2. **RecurringBooking model** (`app/models/recurring_booking.rb`) — Belongs to client and provider, has many requests. Validates session_count is exactly 5.

3. **Request model** (`app/models/request.rb`) — Added optional `belongs_to :recurring_booking` association.

4. **RecurringBookings::CreateService** (`app/services/recurring_bookings/create_service.rb`) — Creates the recurring booking and 5 individual requests scheduled 1 week apart, all in a single transaction. Notifies the provider for each request.

5. **API controller** (`app/controllers/api/recurring_bookings_controller.rb`) — Endpoints for `index`, `show`, and `create`. The `create` endpoint accepts the same params as a regular request (`scheduled_at`, `duration_minutes`, `location`, `notes`) plus `provider_id`.

6. **Route** — `POST /api/recurring_bookings`, `GET /api/recurring_bookings`, `GET /api/recurring_bookings/:id`

7. **Specs** (`spec/services/recurring_bookings/create_service_spec.rb`) — 9 tests covering: creation of the booking and 5 requests, weekly scheduling intervals, consistent attributes across requests, provider notifications, and error handling.

Each of the 5 requests remains independent — providers can accept or decline them individually.

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/recurring_bookings_controller.rb b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..1abd2fa
--- /dev/null
+++ b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,76 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      client = current_client!
+      return if performed?
+
+      bookings = RecurringBooking.where(client: client)
+        .includes(:requests)
+        .order(created_at: :desc)
+
+      render json: bookings.map { |b| recurring_booking_json(b) }
+    end
+
+    def show
+      client = current_client!
+      return if performed?
+
+      booking = RecurringBooking.find_by(id: params[:id], client_id: client.id)
+      return render_not_found unless booking
+
+      render json: recurring_booking_detail_json(booking)
+    end
+
+    def create
+      client = current_client!
+      return if performed?
+
+      provider = Provider.find_by(id: params[:provider_id])
+      return render_not_found unless provider
+
+      result = RecurringBookings::CreateService.new(
+        client: client,
+        provider: provider,
+        params: recurring_booking_params
+      ).call
+
+      if result[:success]
+        render json: recurring_booking_detail_json(result[:recurring_booking]), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
+    private
+
+    def recurring_booking_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes)
+    end
+
+    def recurring_booking_json(booking)
+      {
+        id: booking.id,
+        provider_id: booking.provider_id,
+        client_id: booking.client_id,
+        start_at: booking.start_at,
+        duration_minutes: booking.duration_minutes,
+        session_count: booking.session_count,
+        created_at: booking.created_at
+      }
+    end
+
+    def recurring_booking_detail_json(booking)
+      recurring_booking_json(booking).merge(
+        location: booking.location,
+        notes: booking.notes,
+        requests: booking.requests.order(:scheduled_at).map do |r|
+          {
+            id: r.id,
+            state: r.state,
+            scheduled_at: r.scheduled_at
+          }
+        end
+      )
+    end
+  end
+end
diff --git a/app_bravo/app/models/recurring_booking.rb b/app_bravo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..12da4d6
--- /dev/null
+++ b/app_bravo/app/models/recurring_booking.rb
@@ -0,0 +1,9 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :start_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :session_count, presence: true, numericality: { equal_to: 5 }
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
diff --git a/app_bravo/app/services/recurring_bookings/create_service.rb b/app_bravo/app/services/recurring_bookings/create_service.rb
new file mode 100644
index 0000000..9142566
--- /dev/null
+++ b/app_bravo/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,48 @@
+module RecurringBookings
+  class CreateService
+    SESSIONS = 5
+    WEEK_INTERVAL = 1.week
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      recurring_booking = RecurringBooking.new(
+        client: @client,
+        provider: @provider,
+        start_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes],
+        location: @params[:location],
+        notes: @params[:notes],
+        session_count: SESSIONS
+      )
+
+      RecurringBooking.transaction do
+        recurring_booking.save!
+
+        requests = SESSIONS.times.map do |i|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: Time.parse(@params[:scheduled_at].to_s) + (i * WEEK_INTERVAL),
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes]
+          )
+        end
+
+        requests.each do |request|
+          NotificationService.notify(@provider, :request_created, request_id: request.id)
+        end
+      end
+
+      { success: true, recurring_booking: recurring_booking.reload }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/app_bravo/config/routes.rb b/app_bravo/config/routes.rb
index 8d32af9..75c5fd7 100644
--- a/app_bravo/config/routes.rb
+++ b/app_bravo/config/routes.rb
@@ -29,6 +29,8 @@
     end
 
     resources :payments, only: [:index, :show]
+
+    resources :recurring_bookings, only: [:index, :show, :create]
   end
 
   namespace :admin do
diff --git a/app_bravo/db/migrate/20260408140807_create_recurring_bookings.rb b/app_bravo/db/migrate/20260408140807_create_recurring_bookings.rb
new file mode 100644
index 0000000..25b0b80
--- /dev/null
+++ b/app_bravo/db/migrate/20260408140807_create_recurring_bookings.rb
@@ -0,0 +1,17 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.integer :session_count, null: false, default: 5
+      t.string :location
+      t.text :notes
+      t.integer :duration_minutes, null: false
+      t.datetime :start_at, null: false
+
+      t.timestamps
+    end
+
+    add_reference :requests, :recurring_booking, foreign_key: true
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..22aa5fb 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_08_140807) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -92,6 +92,20 @@
     t.index ["email"], name: "index_providers_on_email", unique: true
   end
 
+  create_table "recurring_bookings", force: :cascade do |t|
+    t.integer "client_id", null: false
+    t.datetime "created_at", null: false
+    t.integer "duration_minutes", null: false
+    t.string "location"
+    t.text "notes"
+    t.integer "provider_id", null: false
+    t.integer "session_count", default: 5, null: false
+    t.datetime "start_at", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "client_id", null: false
@@ -102,11 +116,13 @@
     t.string "location"
     t.text "notes"
     t.integer "provider_id", null: false
+    t.integer "recurring_booking_id"
     t.datetime "scheduled_at", null: false
     t.string "state", default: "pending", null: false
     t.datetime "updated_at", null: false
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_booking_id"], name: "index_requests_on_recurring_booking_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
   end
@@ -130,7 +146,10 @@
   add_foreign_key "orders", "requests"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "orders"
+  add_foreign_key "recurring_bookings", "clients"
+  add_foreign_key "recurring_bookings", "providers"
   add_foreign_key "requests", "clients"
   add_foreign_key "requests", "providers"
+  add_foreign_key "requests", "recurring_bookings"
   add_foreign_key "reviews", "orders"
 end
diff --git a/app_bravo/spec/factories/recurring_bookings.rb b/app_bravo/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..c9bcf18
--- /dev/null
+++ b/app_bravo/spec/factories/recurring_bookings.rb
@@ -0,0 +1,11 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    start_at { 3.days.from_now }
+    duration_minutes { 120 }
+    session_count { 5 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+  end
+end
diff --git a/app_bravo/spec/services/recurring_bookings/create_service_spec.rb b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..d164007
--- /dev/null
+++ b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,78 @@
+require "rails_helper"
+
+RSpec.describe RecurringBookings::CreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now.change(hour: 10) }
+  let(:params) do
+    {
+      scheduled_at: scheduled_at.iso8601,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly recurring session"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: params).call }
+
+  describe "#call" do
+    context "with valid params" do
+      it "creates a recurring booking" do
+        expect { result }.to change(RecurringBooking, :count).by(1)
+      end
+
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+
+      it "returns success" do
+        expect(result[:success]).to be true
+        expect(result[:recurring_booking]).to be_a(RecurringBooking)
+      end
+
+      it "schedules requests one week apart" do
+        booking = result[:recurring_booking]
+        scheduled_times = booking.requests.order(:scheduled_at).pluck(:scheduled_at)
+
+        scheduled_times.each_cons(2) do |earlier, later|
+          expect(later - earlier).to be_within(1.second).of(1.week)
+        end
+      end
+
+      it "sets the same duration, location, and notes on all requests" do
+        booking = result[:recurring_booking]
+        booking.requests.each do |request|
+          expect(request.duration_minutes).to eq(120)
+          expect(request.location).to eq("123 Main St")
+          expect(request.notes).to eq("Weekly recurring session")
+        end
+      end
+
+      it "associates all requests with the recurring booking" do
+        booking = result[:recurring_booking]
+        expect(booking.requests.count).to eq(5)
+      end
+
+      it "notifies the provider for each request" do
+        result
+        log = read_notification_log
+        expect(log.scan("[PUSH]").count { |_| true }).to be >= 5
+        expect(log.scan(/\[PUSH\].*event=request_created/).count).to eq(5)
+      end
+    end
+
+    context "with invalid params" do
+      let(:params) { { scheduled_at: nil, duration_minutes: nil } }
+
+      it "returns errors" do
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
