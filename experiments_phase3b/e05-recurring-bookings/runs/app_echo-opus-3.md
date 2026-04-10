# Experiment: e05-recurring-bookings
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_echo/opus/run-3

---

## Claude Output

Implementation complete. Here's a summary of what was added:

**New files:**
- `db/migrate/20260410131553_create_recurring_bookings.rb` — creates `recurring_bookings` table and adds `recurring_booking_id` FK to `requests`
- `app/models/recurring_booking.rb` — model with associations, validations, and `SESSIONS_COUNT = 5` constant
- `app/services/recurring_bookings/create_service.rb` — creates a `RecurringBooking` + 5 weekly `Request` records in a single transaction, notifies the provider
- `app/controllers/api/recurring_bookings_controller.rb` — `index`, `show`, `create` endpoints (client creates, both client and provider can view)
- `spec/models/recurring_booking_spec.rb` — model validations/associations tests
- `spec/services/recurring_bookings/create_service_spec.rb` — service tests (21 examples)
- `spec/factories/recurring_bookings.rb` — factory

**Modified files:**
- `app/models/request.rb` — added `belongs_to :recurring_booking, optional: true`
- `app/controllers/api/requests_controller.rb` — added `recurring_booking_id` to detail JSON
- `config/routes.rb` — added `resources :recurring_bookings, only: [:index, :show, :create]`

**API usage:**
```
POST /api/recurring_bookings
{
  "provider_id": 1,
  "scheduled_at": "2026-04-15T10:00:00Z",
  "duration_minutes": 60,
  "location": "123 Main St",
  "amount_cents": 200000,
  "notes": "Weekly session"
}
```
This creates a recurring booking with 5 individual requests scheduled weekly (Apr 15, 22, 29, May 6, 13). Each request follows the normal lifecycle (accept, start, complete, etc.) independently.

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/recurring_bookings_controller.rb b/app_echo/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..1c0c354
--- /dev/null
+++ b/app_echo/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,88 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      recurring_bookings = scoped_recurring_bookings.sorted.page(params[:page])
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
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+    end
+
+    def recurring_booking_summary_json(recurring_booking)
+      {
+        id: recurring_booking.id,
+        scheduled_at: recurring_booking.scheduled_at,
+        duration_minutes: recurring_booking.duration_minutes,
+        amount_cents: recurring_booking.amount_cents,
+        currency: recurring_booking.currency,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        sessions_count: recurring_booking.requests.count,
+        created_at: recurring_booking.created_at
+      }
+    end
+
+    def recurring_booking_detail_json(recurring_booking)
+      {
+        id: recurring_booking.id,
+        scheduled_at: recurring_booking.scheduled_at,
+        duration_minutes: recurring_booking.duration_minutes,
+        location: recurring_booking.location,
+        notes: recurring_booking.notes,
+        amount_cents: recurring_booking.amount_cents,
+        currency: recurring_booking.currency,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        requests: recurring_booking.requests.sorted.map do |r|
+          {
+            id: r.id,
+            state: r.state,
+            scheduled_at: r.scheduled_at,
+            amount_cents: r.amount_cents,
+            currency: r.currency
+          }
+        end,
+        created_at: recurring_booking.created_at,
+        updated_at: recurring_booking.updated_at
+      }
+    end
+  end
+end
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..d8b7823 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -162,6 +162,7 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_booking_id: request.recurring_booking_id,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
diff --git a/app_echo/app/models/recurring_booking.rb b/app_echo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..5552935
--- /dev/null
+++ b/app_echo/app/models/recurring_booking.rb
@@ -0,0 +1,16 @@
+class RecurringBooking < ApplicationRecord
+  include Paginatable
+
+  SESSIONS_COUNT = 5
+
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :scheduled_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
+  validates :currency, presence: true
+
+  scope :sorted, -> { order(created_at: :desc) }
+end
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..8785a36 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -5,6 +5,7 @@ class Request < ApplicationRecord
   belongs_to :client
   belongs_to :provider
   belongs_to :announcement, optional: true
+  belongs_to :recurring_booking, optional: true
   has_one :payment, dependent: :destroy
   has_many :reviews, dependent: :destroy
 
diff --git a/app_echo/app/services/recurring_bookings/create_service.rb b/app_echo/app/services/recurring_bookings/create_service.rb
new file mode 100644
index 0000000..1ba8239
--- /dev/null
+++ b/app_echo/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,49 @@
+module RecurringBookings
+  class CreateService
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
+          provider: @provider,
+          scheduled_at: @params[:scheduled_at],
+          duration_minutes: @params[:duration_minutes],
+          location: @params[:location],
+          notes: @params[:notes],
+          amount_cents: @params[:amount_cents],
+          currency: @params[:currency] || "RUB"
+        )
+
+        requests = RecurringBooking::SESSIONS_COUNT.times.map do |week_offset|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: Time.parse(@params[:scheduled_at].to_s) + week_offset.weeks,
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
+          sessions_count: RecurringBooking::SESSIONS_COUNT
+        )
+
+        { success: true, recurring_booking: recurring_booking, requests: requests }
+      end
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/app_echo/config/routes.rb b/app_echo/config/routes.rb
index da43a53..2d01736 100644
--- a/app_echo/config/routes.rb
+++ b/app_echo/config/routes.rb
@@ -24,6 +24,8 @@
 
     resources :payments, only: [:index, :show]
 
+    resources :recurring_bookings, only: [:index, :show, :create]
+
     resources :announcements, only: [:index, :show, :create] do
       member do
         patch :publish
diff --git a/app_echo/db/migrate/20260410131553_create_recurring_bookings.rb b/app_echo/db/migrate/20260410131553_create_recurring_bookings.rb
new file mode 100644
index 0000000..b1496a3
--- /dev/null
+++ b/app_echo/db/migrate/20260410131553_create_recurring_bookings.rb
@@ -0,0 +1,23 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.integer :client_id, null: false
+      t.integer :provider_id, null: false
+      t.integer :duration_minutes, null: false
+      t.string :location
+      t.integer :amount_cents, null: false
+      t.string :currency, default: "RUB", null: false
+      t.datetime :scheduled_at, null: false
+      t.text :notes
+
+      t.timestamps
+    end
+    add_index :recurring_bookings, :client_id
+    add_index :recurring_bookings, :provider_id
+
+    add_foreign_key :recurring_bookings, :clients
+    add_foreign_key :recurring_bookings, :providers
+
+    add_reference :requests, :recurring_booking, foreign_key: true, null: true
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..ba45d74 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_131553) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -86,6 +86,21 @@
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
+    t.datetime "scheduled_at", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "amount_cents", null: false
@@ -102,6 +117,7 @@
     t.text "notes"
     t.integer "proposed_amount_cents"
     t.integer "provider_id", null: false
+    t.integer "recurring_booking_id"
     t.text "reject_reason"
     t.text "response_message"
     t.datetime "scheduled_at", null: false
@@ -111,6 +127,7 @@
     t.index ["announcement_id"], name: "index_requests_on_announcement_id"
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_booking_id"], name: "index_requests_on_recurring_booking_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
   end
@@ -132,8 +149,11 @@
   add_foreign_key "cards", "clients"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "requests"
+  add_foreign_key "recurring_bookings", "clients"
+  add_foreign_key "recurring_bookings", "providers"
   add_foreign_key "requests", "announcements"
   add_foreign_key "requests", "clients"
   add_foreign_key "requests", "providers"
+  add_foreign_key "requests", "recurring_bookings"
   add_foreign_key "reviews", "requests"
 end
diff --git a/app_echo/spec/factories/recurring_bookings.rb b/app_echo/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..70c9b37
--- /dev/null
+++ b/app_echo/spec/factories/recurring_bookings.rb
@@ -0,0 +1,12 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    scheduled_at { 3.days.from_now }
+    duration_minutes { 120 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+    amount_cents { 350_000 }
+    currency { "RUB" }
+  end
+end
diff --git a/app_echo/spec/models/recurring_booking_spec.rb b/app_echo/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..601bff1
--- /dev/null
+++ b/app_echo/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,24 @@
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
+    it { is_expected.to validate_presence_of(:scheduled_at) }
+    it { is_expected.to validate_presence_of(:duration_minutes) }
+    it { is_expected.to validate_numericality_of(:duration_minutes).is_greater_than(0) }
+    it { is_expected.to validate_presence_of(:amount_cents) }
+    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
+    it { is_expected.to validate_presence_of(:currency) }
+  end
+
+  describe "SESSIONS_COUNT" do
+    it "is 5" do
+      expect(RecurringBooking::SESSIONS_COUNT).to eq(5)
+    end
+  end
+end
diff --git a/app_echo/spec/services/recurring_bookings/create_service_spec.rb b/app_echo/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..c95966e
--- /dev/null
+++ b/app_echo/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,107 @@
+require "rails_helper"
+
+RSpec.describe RecurringBookings::CreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now.beginning_of_hour }
+  let(:valid_params) do
+    {
+      scheduled_at: scheduled_at,
+      duration_minutes: 60,
+      location: "456 Oak Ave",
+      notes: "Weekly coaching session",
+      amount_cents: 200_000,
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
+        requests = result[:requests]
+        5.times do |i|
+          expected_time = scheduled_at + i.weeks
+          expect(requests[i].scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "links all requests to the recurring booking" do
+        recurring_booking = result[:recurring_booking]
+        requests = result[:requests]
+        requests.each do |request|
+          expect(request.recurring_booking_id).to eq(recurring_booking.id)
+        end
+      end
+
+      it "sets the same attributes on all requests" do
+        requests = result[:requests]
+        requests.each do |request|
+          expect(request.duration_minutes).to eq(60)
+          expect(request.location).to eq("456 Oak Ave")
+          expect(request.amount_cents).to eq(200_000)
+          expect(request.currency).to eq("RUB")
+          expect(request.client_id).to eq(client.id)
+          expect(request.provider_id).to eq(provider.id)
+        end
+      end
+
+      it "creates all requests in pending state" do
+        requests = result[:requests]
+        requests.each do |request|
+          expect(request.state).to eq("pending")
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
+
+    context "with default currency" do
+      let(:valid_params) do
+        {
+          scheduled_at: scheduled_at,
+          duration_minutes: 60,
+          location: "456 Oak Ave",
+          amount_cents: 200_000
+        }
+      end
+
+      it "defaults currency to RUB" do
+        expect(result[:recurring_booking].currency).to eq("RUB")
+        result[:requests].each do |request|
+          expect(request.currency).to eq("RUB")
+        end
+      end
+    end
+  end
+end
```
