# Experiment: e05-recurring-bookings
# App: app_echo | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_echo/opus/run-3

---

## Claude Output

Implementation complete. Here's what was added:

**New endpoint:** `POST /api/requests/recurring`

**Request body** (same as single request creation):
```json
{
  "provider_id": 1,
  "scheduled_at": "2026-04-16T14:00:00+03:00",
  "duration_minutes": 120,
  "location": "123 Main St",
  "notes": "Weekly session",
  "amount_cents": 350000,
  "currency": "RUB"
}
```

**What it does:**
- Creates a `RecurringBooking` record (group container) storing the recurring schedule metadata
- Creates 5 individual `Request` records, each spaced 1 week apart starting from `scheduled_at`
- All 5 requests are linked via `recurring_booking_id` and managed independently (each can be accepted/declined/canceled separately)
- Everything runs in a transaction — if any request fails validation, nothing is created
- Provider gets a `recurring_booking_created` notification

**Files changed/created:**
- `db/migrate/20260409120000_create_recurring_bookings.rb` — new table + FK on requests
- `app/models/recurring_booking.rb` — new model with validations
- `app/models/request.rb` — added `belongs_to :recurring_booking` association
- `app/models/client.rb` / `provider.rb` — added `has_many :recurring_bookings`
- `app/services/requests/create_recurring_service.rb` — service creating the group + 5 requests
- `app/controllers/api/requests_controller.rb` — new `create_recurring` action, `recurring_booking_id` in JSON
- `config/routes.rb` — added `POST /api/requests/recurring`
- Specs: model spec, service spec, factory (26 new examples, 163 total passing)

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..24ce2ac 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -34,6 +34,26 @@ def create
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
+        render json: recurring_booking_json(result[:recurring_booking], result[:requests]), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def accept
       actor = current_user
       result = Requests::AcceptService.new(request: @request, actor: actor).call
@@ -162,6 +182,7 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_booking_id: request.recurring_booking_id,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
@@ -172,5 +193,24 @@ def request_detail_json(request)
         updated_at: request.updated_at
       }
     end
+
+    def recurring_booking_json(recurring_booking, requests)
+      {
+        id: recurring_booking.id,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        total_sessions: recurring_booking.total_sessions,
+        day_of_week: recurring_booking.day_of_week,
+        time_of_day: recurring_booking.time_of_day,
+        duration_minutes: recurring_booking.duration_minutes,
+        location: recurring_booking.location,
+        notes: recurring_booking.notes,
+        amount_cents: recurring_booking.amount_cents,
+        currency: recurring_booking.currency,
+        requests: requests.map { |r| request_summary_json(r) },
+        created_at: recurring_booking.created_at,
+        updated_at: recurring_booking.updated_at
+      }
+    end
   end
 end
diff --git a/app_echo/app/models/client.rb b/app_echo/app/models/client.rb
index e0c7a6b..cf62d1b 100644
--- a/app_echo/app/models/client.rb
+++ b/app_echo/app/models/client.rb
@@ -2,6 +2,7 @@ class Client < ApplicationRecord
   serialize :notification_preferences, coder: JSON
 
   has_many :requests, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
   has_many :announcements, dependent: :destroy
   has_many :cards, dependent: :destroy
 
diff --git a/app_echo/app/models/provider.rb b/app_echo/app/models/provider.rb
index b093865..9d460ba 100644
--- a/app_echo/app/models/provider.rb
+++ b/app_echo/app/models/provider.rb
@@ -2,6 +2,7 @@ class Provider < ApplicationRecord
   serialize :notification_preferences, coder: JSON
 
   has_many :requests, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
 
   validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
   validates :name, presence: true
diff --git a/app_echo/app/models/recurring_booking.rb b/app_echo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..266f5b5
--- /dev/null
+++ b/app_echo/app/models/recurring_booking.rb
@@ -0,0 +1,12 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :total_sessions, presence: true, numericality: { equal_to: 5 }
+  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
+  validates :time_of_day, presence: true, format: { with: /\A\d{2}:\d{2}\z/, message: "must be HH:MM format" }
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
+  validates :currency, presence: true
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
 
diff --git a/app_echo/app/services/requests/create_recurring_service.rb b/app_echo/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..ad95544
--- /dev/null
+++ b/app_echo/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,67 @@
+module Requests
+  class CreateRecurringService
+    TOTAL_SESSIONS = 5
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      ActiveRecord::Base.transaction do
+        recurring_booking = create_recurring_booking!
+        requests = create_requests!(recurring_booking)
+
+        NotificationService.notify(
+          @provider,
+          :recurring_booking_created,
+          recurring_booking_id: recurring_booking.id,
+          total_sessions: TOTAL_SESSIONS
+        )
+
+        { success: true, recurring_booking: recurring_booking, requests: requests }
+      end
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def create_recurring_booking!
+      first_scheduled_at = Time.zone.parse(@params[:scheduled_at].to_s) if @params[:scheduled_at].present?
+      RecurringBooking.create!(
+        client: @client,
+        provider: @provider,
+        total_sessions: TOTAL_SESSIONS,
+        day_of_week: first_scheduled_at&.wday,
+        time_of_day: first_scheduled_at&.strftime("%H:%M"),
+        duration_minutes: @params[:duration_minutes],
+        location: @params[:location],
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents],
+        currency: @params[:currency] || "RUB"
+      )
+    end
+
+    def create_requests!(recurring_booking)
+      first_scheduled_at = Time.zone.parse(@params[:scheduled_at].to_s) if @params[:scheduled_at].present?
+
+      TOTAL_SESSIONS.times.map do |i|
+        scheduled_at = first_scheduled_at + i.weeks
+
+        Request.create!(
+          client: @client,
+          provider: @provider,
+          recurring_booking: recurring_booking,
+          scheduled_at: scheduled_at,
+          duration_minutes: @params[:duration_minutes],
+          location: @params[:location],
+          notes: @params[:notes],
+          amount_cents: @params[:amount_cents],
+          currency: @params[:currency] || "RUB"
+        )
+      end
+    end
+  end
+end
diff --git a/app_echo/config/routes.rb b/app_echo/config/routes.rb
index da43a53..71d214d 100644
--- a/app_echo/config/routes.rb
+++ b/app_echo/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :recurring, action: :create_recurring
+      end
       member do
         patch :accept
         patch :decline
diff --git a/app_echo/db/migrate/20260409120000_create_recurring_bookings.rb b/app_echo/db/migrate/20260409120000_create_recurring_bookings.rb
new file mode 100644
index 0000000..086635d
--- /dev/null
+++ b/app_echo/db/migrate/20260409120000_create_recurring_bookings.rb
@@ -0,0 +1,20 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.integer :total_sessions, null: false, default: 5
+      t.integer :day_of_week, null: false
+      t.string :time_of_day, null: false
+      t.integer :duration_minutes, null: false
+      t.string :location
+      t.text :notes
+      t.integer :amount_cents, null: false
+      t.string :currency, null: false, default: "RUB"
+
+      t.timestamps
+    end
+
+    add_reference :requests, :recurring_booking, null: true, foreign_key: true
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index c2c99cb..70301ab 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_084335) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_120000) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -86,6 +86,23 @@
     t.index ["email"], name: "index_providers_on_email", unique: true
   end
 
+  create_table "recurring_bookings", force: :cascade do |t|
+    t.integer "amount_cents", null: false
+    t.integer "client_id", null: false
+    t.datetime "created_at", null: false
+    t.string "currency", default: "RUB", null: false
+    t.integer "day_of_week", null: false
+    t.integer "duration_minutes", null: false
+    t.string "location"
+    t.text "notes"
+    t.integer "provider_id", null: false
+    t.string "time_of_day", null: false
+    t.integer "total_sessions", default: 5, null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "amount_cents", null: false
@@ -102,6 +119,7 @@
     t.text "notes"
     t.integer "proposed_amount_cents"
     t.integer "provider_id", null: false
+    t.integer "recurring_booking_id"
     t.string "recurring_group_id"
     t.integer "recurring_index"
     t.text "reject_reason"
@@ -115,6 +133,7 @@
     t.index ["announcement_id"], name: "index_requests_on_announcement_id"
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_booking_id"], name: "index_requests_on_recurring_booking_id"
     t.index ["recurring_group_id"], name: "index_requests_on_recurring_group_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
@@ -137,8 +156,11 @@
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
index 0000000..e5d18d0
--- /dev/null
+++ b/app_echo/spec/factories/recurring_bookings.rb
@@ -0,0 +1,14 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    total_sessions { 5 }
+    day_of_week { 3 }
+    time_of_day { "14:00" }
+    duration_minutes { 120 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+    amount_cents { 350_000 }
+    currency { "RUB" }
+  end
+end
diff --git a/app_echo/spec/models/recurring_booking_spec.rb b/app_echo/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..281201b
--- /dev/null
+++ b/app_echo/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,37 @@
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
+    it { is_expected.to validate_presence_of(:total_sessions) }
+    it { is_expected.to validate_numericality_of(:total_sessions).is_equal_to(5) }
+    it { is_expected.to validate_presence_of(:day_of_week) }
+    it { is_expected.to validate_presence_of(:time_of_day) }
+    it { is_expected.to validate_presence_of(:duration_minutes) }
+    it { is_expected.to validate_numericality_of(:duration_minutes).is_greater_than(0) }
+    it { is_expected.to validate_presence_of(:amount_cents) }
+    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
+    it { is_expected.to validate_presence_of(:currency) }
+
+    it "validates time_of_day format" do
+      booking = build(:recurring_booking, time_of_day: "invalid")
+      expect(booking).not_to be_valid
+      expect(booking.errors[:time_of_day]).to include("must be HH:MM format")
+    end
+
+    it "accepts valid time_of_day" do
+      booking = build(:recurring_booking, time_of_day: "14:30")
+      expect(booking).to be_valid
+    end
+
+    it "validates day_of_week inclusion" do
+      booking = build(:recurring_booking, day_of_week: 7)
+      expect(booking).not_to be_valid
+    end
+  end
+end
diff --git a/app_echo/spec/services/requests/create_recurring_service_spec.rb b/app_echo/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..80e9824
--- /dev/null
+++ b/app_echo/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,108 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now.change(hour: 14, min: 0) }
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
+      it "sets correct recurring booking attributes" do
+        booking = result[:recurring_booking]
+        expect(booking.total_sessions).to eq(5)
+        expect(booking.day_of_week).to eq(scheduled_at.wday)
+        expect(booking.time_of_day).to eq("14:00")
+        expect(booking.duration_minutes).to eq(120)
+        expect(booking.amount_cents).to eq(350_000)
+        expect(booking.client).to eq(client)
+        expect(booking.provider).to eq(provider)
+      end
+
+      it "creates requests spaced one week apart" do
+        requests = result[:requests]
+        expect(requests.size).to eq(5)
+
+        requests.each_with_index do |req, i|
+          expected_time = scheduled_at + i.weeks
+          expect(req.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "links all requests to the recurring booking" do
+        booking = result[:recurring_booking]
+        requests = result[:requests]
+        requests.each do |req|
+          expect(req.recurring_booking).to eq(booking)
+        end
+      end
+
+      it "creates all requests in pending state" do
+        result[:requests].each do |req|
+          expect(req.state).to eq("pending")
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
+        expect { result }.not_to change(Request, :count)
+        expect { result }.not_to change(RecurringBooking, :count)
+      end
+    end
+
+    context "with default currency" do
+      let(:valid_params) do
+        {
+          scheduled_at: scheduled_at.iso8601,
+          duration_minutes: 60,
+          location: "456 Oak Ave",
+          amount_cents: 200_000
+        }
+      end
+
+      it "defaults to RUB" do
+        booking = result[:recurring_booking]
+        expect(booking.currency).to eq("RUB")
+        result[:requests].each do |req|
+          expect(req.currency).to eq("RUB")
+        end
+      end
+    end
+  end
+end
```
