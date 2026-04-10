# Experiment: e05-recurring-bookings
# App: app_bravo | Model: opus | Run: 1
# Branch: debt_experiment/e05-recurring-bookings/app_bravo/opus/run-1

---

## Claude Output

All 138 tests pass (14 new + 124 existing). Here's what was implemented:

**Recurring Weekly Bookings — 5 sessions with the same provider at the same time**

### New files:
- `db/migrate/20260410081135_create_recurring_bookings.rb` — creates `recurring_bookings` table and adds `recurring_booking_id` FK to `requests`
- `app/models/recurring_booking.rb` — model with client/provider associations, validations (exactly 5 recurrences), and scopes
- `app/services/recurring_bookings/create_service.rb` — atomically creates a `RecurringBooking` + 5 `Request` records at weekly intervals, notifies the provider
- `app/controllers/api/recurring_bookings_controller.rb` — `index`, `show`, `create` endpoints
- `spec/models/recurring_booking_spec.rb` — model validations/associations
- `spec/services/recurring_bookings/create_service_spec.rb` — service behavior (creates 5 weekly requests, notifications, error handling)
- `spec/factories/recurring_bookings.rb` — factory

### Modified files:
- `app/models/request.rb` — added `belongs_to :recurring_booking, optional: true`
- `config/routes.rb` — added `resources :recurring_bookings`

### API:
- `POST /api/recurring_bookings` — params: `provider_id`, `scheduled_at`, `duration_minutes`, `location`, `notes`
- `GET /api/recurring_bookings` — lists recurring bookings for the current user
- `GET /api/recurring_bookings/:id` — shows detail including all child requests

### Design decisions:
- Each of the 5 requests is independent — the provider can accept/decline each individually
- The recurring booking is created transactionally (all-or-nothing)
- `recurrence_count` is fixed at 5 per the requirement
- Requests are scheduled at `start_time + 0/1/2/3/4 weeks`

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/recurring_bookings_controller.rb b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..5043e50
--- /dev/null
+++ b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,82 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      bookings = scoped_bookings.sorted.page(params[:page])
+      render json: bookings.map { |b| booking_summary_json(b) }
+    end
+
+    def show
+      booking = RecurringBooking.find_by(id: params[:id])
+      return render_not_found unless booking
+
+      render json: booking_detail_json(booking)
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
+        params: booking_params
+      ).call
+
+      if result[:success]
+        render json: booking_detail_json(result[:recurring_booking]), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
+    private
+
+    def scoped_bookings
+      if current_user.is_a?(Client)
+        RecurringBooking.where(client: current_user)
+      else
+        RecurringBooking.where(provider: current_user)
+      end
+    end
+
+    def booking_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes)
+    end
+
+    def booking_summary_json(booking)
+      {
+        id: booking.id,
+        start_at: booking.start_at,
+        duration_minutes: booking.duration_minutes,
+        recurrence_count: booking.recurrence_count,
+        client_id: booking.client_id,
+        provider_id: booking.provider_id
+      }
+    end
+
+    def booking_detail_json(booking)
+      {
+        id: booking.id,
+        start_at: booking.start_at,
+        duration_minutes: booking.duration_minutes,
+        location: booking.location,
+        notes: booking.notes,
+        recurrence_count: booking.recurrence_count,
+        client_id: booking.client_id,
+        provider_id: booking.provider_id,
+        requests: booking.requests.sorted.map do |r|
+          {
+            id: r.id,
+            state: r.state,
+            scheduled_at: r.scheduled_at
+          }
+        end,
+        created_at: booking.created_at,
+        updated_at: booking.updated_at
+      }
+    end
+  end
+end
diff --git a/app_bravo/app/models/recurring_booking.rb b/app_bravo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..206898a
--- /dev/null
+++ b/app_bravo/app/models/recurring_booking.rb
@@ -0,0 +1,15 @@
+class RecurringBooking < ApplicationRecord
+  include Paginatable
+
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :start_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :recurrence_count, presence: true, numericality: { equal_to: 5 }
+
+  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
+  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
+  scope :sorted, -> { order(start_at: :desc) }
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
index 0000000..df135f7
--- /dev/null
+++ b/app_bravo/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,45 @@
+module RecurringBookings
+  class CreateService
+    WEEKS = 5
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
+        recurrence_count: WEEKS
+      )
+
+      RecurringBooking.transaction do
+        recurring_booking.save!
+
+        WEEKS.times do |i|
+          scheduled_at = Time.parse(@params[:scheduled_at].to_s) + i.weeks
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: scheduled_at,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes]
+          )
+        end
+      end
+
+      NotificationService.notify(@provider, :recurring_booking_created, recurring_booking_id: recurring_booking.id)
+      { success: true, recurring_booking: recurring_booking }
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
diff --git a/app_bravo/db/migrate/20260410081135_create_recurring_bookings.rb b/app_bravo/db/migrate/20260410081135_create_recurring_bookings.rb
new file mode 100644
index 0000000..94381cb
--- /dev/null
+++ b/app_bravo/db/migrate/20260410081135_create_recurring_bookings.rb
@@ -0,0 +1,16 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.datetime :start_at, null: false
+      t.integer :duration_minutes, null: false
+      t.string :location
+      t.text :notes
+      t.integer :recurrence_count, null: false, default: 5
+      t.timestamps
+    end
+
+    add_reference :requests, :recurring_booking, foreign_key: true
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..e41ec77 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140806) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_081135) do
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
+    t.integer "recurrence_count", default: 5, null: false
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
index 0000000..0f07fc7
--- /dev/null
+++ b/app_bravo/spec/factories/recurring_bookings.rb
@@ -0,0 +1,11 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    start_at { 3.days.from_now }
+    duration_minutes { 120 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+    recurrence_count { 5 }
+  end
+end
diff --git a/app_bravo/spec/models/recurring_booking_spec.rb b/app_bravo/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..a0a1b1a
--- /dev/null
+++ b/app_bravo/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,17 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking, type: :model do
+  describe "associations" do
+    it { is_expected.to belong_to(:client) }
+    it { is_expected.to belong_to(:provider) }
+    it { is_expected.to have_many(:requests).dependent(:nullify) }
+  end
+
+  describe "validations" do
+    it { is_expected.to validate_presence_of(:start_at) }
+    it { is_expected.to validate_presence_of(:duration_minutes) }
+    it { is_expected.to validate_numericality_of(:duration_minutes).is_greater_than(0) }
+    it { is_expected.to validate_presence_of(:recurrence_count) }
+    it { is_expected.to validate_numericality_of(:recurrence_count).is_equal_to(5) }
+  end
+end
diff --git a/app_bravo/spec/services/recurring_bookings/create_service_spec.rb b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..006840a
--- /dev/null
+++ b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,67 @@
+require "rails_helper"
+
+RSpec.describe RecurringBookings::CreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:start_time) { 3.days.from_now.beginning_of_hour }
+  let(:valid_params) do
+    {
+      scheduled_at: start_time,
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
+      it "creates a recurring booking" do
+        expect { result }.to change(RecurringBooking, :count).by(1)
+        expect(result[:success]).to be true
+      end
+
+      it "creates 5 requests with weekly intervals" do
+        expect { result }.to change(Request, :count).by(5)
+
+        requests = result[:recurring_booking].requests.order(:scheduled_at)
+        expect(requests.size).to eq(5)
+
+        requests.each_with_index do |request, i|
+          expected_time = start_time + i.weeks
+          expect(request.scheduled_at).to be_within(1.second).of(expected_time)
+          expect(request.duration_minutes).to eq(120)
+          expect(request.location).to eq("123 Main St")
+          expect(request.client).to eq(client)
+          expect(request.provider).to eq(provider)
+        end
+      end
+
+      it "creates all requests in pending state" do
+        result
+        requests = result[:recurring_booking].requests
+        expect(requests.map(&:state).uniq).to eq(["pending"])
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
