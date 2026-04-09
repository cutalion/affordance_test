# Experiment: e05-recurring-bookings
# App: app_bravo | Model: opus | Run: 1
# Branch: debt_experiment/e05-recurring-bookings/app_bravo/opus/run-1

---

## Claude Output

All 138 tests pass. Here's what was implemented:

**New files:**
- `db/migrate/20260409100000_create_recurring_bookings.rb` — creates the `recurring_bookings` table
- `db/migrate/20260409100001_add_recurring_booking_to_requests.rb` — adds `recurring_booking_id` FK to `requests`
- `app/models/recurring_booking.rb` — model with associations to client, provider, and requests; validates exactly 5 sessions
- `app/services/recurring_bookings/create_service.rb` — creates a `RecurringBooking` and 5 `Request` records at weekly intervals, all in a transaction
- `app/controllers/api/recurring_bookings_controller.rb` — index/show/create endpoints
- `spec/models/recurring_booking_spec.rb` — model specs
- `spec/services/recurring_bookings/create_service_spec.rb` — service specs
- `spec/factories/recurring_bookings.rb` — factory

**Modified files:**
- `app/models/request.rb` — added `belongs_to :recurring_booking, optional: true`
- `config/routes.rb` — added `resources :recurring_bookings, only: [:index, :show, :create]`

**How it works:**
1. Client calls `POST /api/recurring_bookings` with `provider_id`, `start_at`, `duration_minutes`, `location`, `notes`
2. The service creates a `RecurringBooking` record and 5 `Request` records scheduled at weekly intervals (same day/time, weeks 0-4)
3. Each request follows the normal accept/decline flow independently — the provider can accept or decline each session individually
4. The provider receives a `recurring_booking_created` notification

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/recurring_bookings_controller.rb b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..4fb989c
--- /dev/null
+++ b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,87 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      recurring_bookings = scoped_recurring_bookings
+        .includes(:requests)
+        .order(created_at: :desc)
+        .page(params[:page])
+
+      render json: recurring_bookings.map { |rb| recurring_booking_summary_json(rb) }
+    end
+
+    def show
+      recurring_booking = scoped_recurring_bookings.find_by(id: params[:id])
+      return render_not_found unless recurring_booking
+
+      render json: recurring_booking_detail_json(recurring_booking)
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
+    def scoped_recurring_bookings
+      if current_user.is_a?(Client)
+        RecurringBooking.where(client: current_user)
+      else
+        RecurringBooking.where(provider: current_user)
+      end
+    end
+
+    def recurring_booking_params
+      params.permit(:start_at, :duration_minutes, :location, :notes)
+    end
+
+    def recurring_booking_summary_json(recurring_booking)
+      {
+        id: recurring_booking.id,
+        start_at: recurring_booking.start_at,
+        duration_minutes: recurring_booking.duration_minutes,
+        total_sessions: recurring_booking.total_sessions,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        requests_count: recurring_booking.requests.size
+      }
+    end
+
+    def recurring_booking_detail_json(recurring_booking)
+      {
+        id: recurring_booking.id,
+        start_at: recurring_booking.start_at,
+        duration_minutes: recurring_booking.duration_minutes,
+        location: recurring_booking.location,
+        notes: recurring_booking.notes,
+        total_sessions: recurring_booking.total_sessions,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        requests: recurring_booking.requests.sorted.map do |request|
+          {
+            id: request.id,
+            state: request.state,
+            scheduled_at: request.scheduled_at
+          }
+        end,
+        created_at: recurring_booking.created_at,
+        updated_at: recurring_booking.updated_at
+      }
+    end
+  end
+end
diff --git a/app_bravo/app/models/recurring_booking.rb b/app_bravo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..b09e34a
--- /dev/null
+++ b/app_bravo/app/models/recurring_booking.rb
@@ -0,0 +1,9 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :destroy
+
+  validates :start_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :total_sessions, presence: true, numericality: { equal_to: 5 }
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
index 0000000..70c9244
--- /dev/null
+++ b/app_bravo/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,50 @@
+module RecurringBookings
+  class CreateService
+    TOTAL_SESSIONS = 5
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
+        start_at: @params[:start_at],
+        duration_minutes: @params[:duration_minutes],
+        location: @params[:location],
+        notes: @params[:notes],
+        total_sessions: TOTAL_SESSIONS
+      )
+
+      RecurringBooking.transaction do
+        recurring_booking.save!
+
+        TOTAL_SESSIONS.times do |i|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: Time.parse(@params[:start_at].to_s) + i.weeks,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes]
+          )
+        end
+      end
+
+      NotificationService.notify(
+        @provider,
+        :recurring_booking_created,
+        recurring_booking_id: recurring_booking.id,
+        total_sessions: TOTAL_SESSIONS
+      )
+
+      { success: true, recurring_booking: recurring_booking }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/app_bravo/config/routes.rb b/app_bravo/config/routes.rb
index 8d32af9..24ea423 100644
--- a/app_bravo/config/routes.rb
+++ b/app_bravo/config/routes.rb
@@ -28,6 +28,8 @@
       resources :reviews, only: [:index, :create]
     end
 
+    resources :recurring_bookings, only: [:index, :show, :create]
+
     resources :payments, only: [:index, :show]
   end
 
diff --git a/app_bravo/db/migrate/20260409100000_create_recurring_bookings.rb b/app_bravo/db/migrate/20260409100000_create_recurring_bookings.rb
new file mode 100644
index 0000000..e7d2479
--- /dev/null
+++ b/app_bravo/db/migrate/20260409100000_create_recurring_bookings.rb
@@ -0,0 +1,15 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.datetime :start_at, null: false
+      t.integer :duration_minutes, null: false
+      t.string :location
+      t.text :notes
+      t.integer :total_sessions, null: false, default: 5
+
+      t.timestamps
+    end
+  end
+end
diff --git a/app_bravo/db/migrate/20260409100001_add_recurring_booking_to_requests.rb b/app_bravo/db/migrate/20260409100001_add_recurring_booking_to_requests.rb
new file mode 100644
index 0000000..7eef7bd
--- /dev/null
+++ b/app_bravo/db/migrate/20260409100001_add_recurring_booking_to_requests.rb
@@ -0,0 +1,5 @@
+class AddRecurringBookingToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_reference :requests, :recurring_booking, null: true, foreign_key: true
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index 667709c..60cd151 100644
--- a/app_bravo/db/schema.rb
+++ b/app_bravo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_075820) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_100001) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -99,8 +99,8 @@
     t.string "location"
     t.text "notes"
     t.integer "provider_id", null: false
-    t.datetime "scheduled_at", null: false
-    t.integer "sessions_count", default: 5, null: false
+    t.datetime "start_at", null: false
+    t.integer "total_sessions", default: 5, null: false
     t.datetime "updated_at", null: false
     t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
     t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
diff --git a/app_bravo/spec/factories/recurring_bookings.rb b/app_bravo/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..6599d21
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
+    total_sessions { 5 }
+  end
+end
diff --git a/app_bravo/spec/models/recurring_booking_spec.rb b/app_bravo/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..7ccf9c7
--- /dev/null
+++ b/app_bravo/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,30 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking, type: :model do
+  describe "associations" do
+    it { is_expected.to belong_to(:client) }
+    it { is_expected.to belong_to(:provider) }
+    it { is_expected.to have_many(:requests).dependent(:destroy) }
+  end
+
+  describe "validations" do
+    subject { build(:recurring_booking) }
+
+    it { is_expected.to validate_presence_of(:start_at) }
+    it { is_expected.to validate_presence_of(:duration_minutes) }
+    it { is_expected.to validate_presence_of(:total_sessions) }
+
+    it "validates duration_minutes is greater than 0" do
+      booking = build(:recurring_booking, duration_minutes: 0)
+      expect(booking).not_to be_valid
+    end
+
+    it "validates total_sessions equals 5" do
+      booking = build(:recurring_booking, total_sessions: 3)
+      expect(booking).not_to be_valid
+
+      booking.total_sessions = 5
+      expect(booking).to be_valid
+    end
+  end
+end
diff --git a/app_bravo/spec/services/recurring_bookings/create_service_spec.rb b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..204b1c6
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
+      start_at: start_time,
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
+      it "creates 5 requests at weekly intervals" do
+        expect { result }.to change(Request, :count).by(5)
+
+        requests = result[:recurring_booking].requests.order(:scheduled_at)
+        expect(requests.size).to eq(5)
+
+        requests.each_with_index do |request, i|
+          expect(request.scheduled_at).to be_within(1.second).of(start_time + i.weeks)
+          expect(request.duration_minutes).to eq(120)
+          expect(request.location).to eq("123 Main St")
+          expect(request.notes).to eq("Weekly session")
+          expect(request.client).to eq(client)
+          expect(request.provider).to eq(provider)
+        end
+      end
+
+      it "associates all requests with the recurring booking" do
+        recurring_booking = result[:recurring_booking]
+        expect(recurring_booking.requests.count).to eq(5)
+        expect(recurring_booking.requests.pluck(:recurring_booking_id).uniq).to eq([recurring_booking.id])
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=recurring_booking_created")
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { start_at: nil, duration_minutes: nil } }
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
