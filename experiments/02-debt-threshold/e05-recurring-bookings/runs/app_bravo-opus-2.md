# Experiment: e05-recurring-bookings
# App: app_bravo | Model: opus | Run: 2
# Branch: debt_experiment/e05-recurring-bookings/app_bravo/opus/run-2

---

## Claude Output

Implementation complete. Here's what was built:

### Recurring Weekly Bookings

**New files:**
- `db/migrate/20260408140807_create_recurring_bookings.rb` — creates `recurring_bookings` table and adds `recurring_booking_id` FK to `requests`
- `app/models/recurring_booking.rb` — model with associations to client, provider, and requests; validates exactly 5 occurrences
- `app/services/recurring_bookings/create_service.rb` — creates the recurring booking and 5 weekly requests in a single transaction, notifies the provider
- `app/controllers/api/recurring_bookings_controller.rb` — index/show/create endpoints
- `spec/models/recurring_booking_spec.rb` — model validation and association tests
- `spec/services/recurring_bookings/create_service_spec.rb` — service tests (scheduling, associations, notifications, error handling)
- `spec/factories/recurring_bookings.rb` — factory

**Modified files:**
- `app/models/request.rb` — added `belongs_to :recurring_booking, optional: true`
- `app/models/client.rb` — added `has_many :recurring_bookings`
- `app/models/provider.rb` — added `has_many :recurring_bookings`
- `config/routes.rb` — added `resources :recurring_bookings, only: [:index, :show, :create]`

**API usage:**
```
POST /api/recurring_bookings
  provider_id, start_at, duration_minutes, location, notes
  → Creates 5 requests scheduled weekly starting from start_at

GET /api/recurring_bookings      → List recurring bookings
GET /api/recurring_bookings/:id  → Show with nested request statuses
```

Each generated request follows the existing workflow — providers can independently accept or decline each session.

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/recurring_bookings_controller.rb b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..a5496ae
--- /dev/null
+++ b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,81 @@
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
+        params: recurring_booking_params
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
+    def recurring_booking_params
+      params.permit(:start_at, :duration_minutes, :location, :notes)
+    end
+
+    def booking_summary_json(booking)
+      {
+        id: booking.id,
+        start_at: booking.start_at,
+        occurrences: booking.occurrences,
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
+        occurrences: booking.occurrences,
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
diff --git a/app_bravo/app/models/client.rb b/app_bravo/app/models/client.rb
index 8c697da..2b7f4ed 100644
--- a/app_bravo/app/models/client.rb
+++ b/app_bravo/app/models/client.rb
@@ -3,6 +3,7 @@ class Client < ApplicationRecord
 
   has_many :requests, dependent: :destroy
   has_many :orders, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
   has_many :cards, dependent: :destroy
   has_many :reviews, as: :author, dependent: :destroy
 
diff --git a/app_bravo/app/models/provider.rb b/app_bravo/app/models/provider.rb
index 2f85142..407f00b 100644
--- a/app_bravo/app/models/provider.rb
+++ b/app_bravo/app/models/provider.rb
@@ -3,6 +3,7 @@ class Provider < ApplicationRecord
 
   has_many :requests, dependent: :destroy
   has_many :orders, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
   has_many :reviews, as: :author, dependent: :destroy
 
   validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
diff --git a/app_bravo/app/models/recurring_booking.rb b/app_bravo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..4fbbfd4
--- /dev/null
+++ b/app_bravo/app/models/recurring_booking.rb
@@ -0,0 +1,15 @@
+class RecurringBooking < ApplicationRecord
+  include Paginatable
+
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :destroy
+
+  validates :start_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :occurrences, presence: true, numericality: { equal_to: 5 }
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
index 0000000..227324a
--- /dev/null
+++ b/app_bravo/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,48 @@
+module RecurringBookings
+  class CreateService
+    WEEKLY_OCCURRENCES = 5
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
+          start_at: @params[:start_at],
+          duration_minutes: @params[:duration_minutes],
+          location: @params[:location],
+          notes: @params[:notes],
+          occurrences: WEEKLY_OCCURRENCES
+        )
+
+        requests = WEEKLY_OCCURRENCES.times.map do |week|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: Time.parse(@params[:start_at].to_s) + week.weeks,
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
+          request_count: requests.size
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
index 0000000..1b0f71d
--- /dev/null
+++ b/app_bravo/db/migrate/20260408140807_create_recurring_bookings.rb
@@ -0,0 +1,17 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.datetime :start_at, null: false
+      t.integer :duration_minutes, null: false
+      t.string :location
+      t.text :notes
+      t.integer :occurrences, null: false, default: 5
+
+      t.timestamps
+    end
+
+    add_reference :requests, :recurring_booking, null: true, foreign_key: true
+  end
+end
diff --git a/app_bravo/db/schema.rb b/app_bravo/db/schema.rb
index cff169b..f459367 100644
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
+    t.integer "occurrences", default: 5, null: false
+    t.integer "provider_id", null: false
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
index 0000000..9a55153
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
+    occurrences { 5 }
+  end
+end
diff --git a/app_bravo/spec/models/recurring_booking_spec.rb b/app_bravo/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..2eb1078
--- /dev/null
+++ b/app_bravo/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,17 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking, type: :model do
+  describe "associations" do
+    it { should belong_to(:client) }
+    it { should belong_to(:provider) }
+    it { should have_many(:requests).dependent(:destroy) }
+  end
+
+  describe "validations" do
+    it { should validate_presence_of(:start_at) }
+    it { should validate_presence_of(:duration_minutes) }
+    it { should validate_numericality_of(:duration_minutes).is_greater_than(0) }
+    it { should validate_presence_of(:occurrences) }
+    it { should validate_numericality_of(:occurrences).is_equal_to(5) }
+  end
+end
diff --git a/app_bravo/spec/services/recurring_bookings/create_service_spec.rb b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..bcf7132
--- /dev/null
+++ b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,77 @@
+require "rails_helper"
+
+RSpec.describe RecurringBookings::CreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:start_time) { 3.days.from_now.beginning_of_hour }
+  let(:valid_params) do
+    {
+      start_at: start_time,
+      duration_minutes: 60,
+      location: "456 Oak Ave",
+      notes: "Weekly coaching session"
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
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+
+      it "schedules requests one week apart" do
+        requests = result[:requests]
+        scheduled_times = requests.map(&:scheduled_at)
+
+        (0..4).each do |week|
+          expect(scheduled_times[week]).to be_within(1.second).of(start_time + week.weeks)
+        end
+      end
+
+      it "associates all requests with the recurring booking" do
+        recurring_booking = result[:recurring_booking]
+        requests = result[:requests]
+        requests.each do |request|
+          expect(request.recurring_booking).to eq(recurring_booking)
+        end
+      end
+
+      it "sets the same provider, client, location, and notes on all requests" do
+        requests = result[:requests]
+        requests.each do |request|
+          expect(request.client).to eq(client)
+          expect(request.provider).to eq(provider)
+          expect(request.location).to eq("456 Oak Ave")
+          expect(request.notes).to eq("Weekly coaching session")
+          expect(request.duration_minutes).to eq(60)
+        end
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
