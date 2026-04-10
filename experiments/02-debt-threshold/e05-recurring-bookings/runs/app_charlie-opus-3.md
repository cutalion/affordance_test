# Experiment: e05-recurring-bookings
# App: app_charlie | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_charlie/opus/run-3

---

## Claude Output

All done. Here's a summary of what was implemented:

## Recurring Weekly Bookings

**New files:**
- `db/migrate/..._create_recurring_bookings.rb` — creates `recurring_bookings` table
- `db/migrate/..._add_recurring_booking_to_requests.rb` — adds nullable `recurring_booking_id` FK to `requests`
- `app/models/recurring_booking.rb` — model with `client`, `provider`, `total_sessions`, and `has_many :requests`
- `app/services/requests/create_recurring_service.rb` — creates a `RecurringBooking` + 5 `Request` records (weekly intervals) in a single transaction
- `app/controllers/api/recurring_bookings_controller.rb` — `index`/`show` endpoints to view recurring bookings
- `spec/models/recurring_booking_spec.rb` — model specs
- `spec/services/requests/create_recurring_service_spec.rb` — service specs (19 examples)
- `spec/factories/recurring_bookings.rb` — factory

**Modified files:**
- `app/models/request.rb` — added `belongs_to :recurring_booking, optional: true`
- `app/controllers/api/requests_controller.rb` — added `recurring` action + `recurring_booking_id` in JSON + `recurring_booking_json` helper
- `config/routes.rb` — added `POST /api/requests/recurring` and `GET /api/recurring_bookings` routes

**API usage:**
```
POST /api/requests/recurring
  provider_id, scheduled_at, duration_minutes, location, notes, amount_cents, currency
  → Creates 5 weekly sessions starting from scheduled_at
```

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/recurring_bookings_controller.rb b/app_charlie/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..98d3e5b
--- /dev/null
+++ b/app_charlie/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,47 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      bookings = scoped_bookings.order(created_at: :desc).page(params[:page])
+      render json: bookings.map { |b| booking_json(b) }
+    end
+
+    def show
+      booking = scoped_bookings.find_by(id: params[:id])
+      return render_not_found unless booking
+
+      render json: booking_json(booking)
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
+    def booking_json(booking)
+      {
+        id: booking.id,
+        total_sessions: booking.total_sessions,
+        client_id: booking.client_id,
+        provider_id: booking.provider_id,
+        requests: booking.requests.order(:scheduled_at).map { |r| request_summary(r) },
+        created_at: booking.created_at,
+        updated_at: booking.updated_at
+      }
+    end
+
+    def request_summary(request)
+      {
+        id: request.id,
+        state: request.state,
+        scheduled_at: request.scheduled_at,
+        amount_cents: request.amount_cents,
+        currency: request.currency
+      }
+    end
+  end
+end
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..ad713fd 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
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
@@ -164,6 +184,7 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_booking_id: request.recurring_booking_id,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
@@ -174,5 +195,17 @@ def request_detail_json(request)
         updated_at: request.updated_at
       }
     end
+
+    def recurring_booking_json(recurring_booking, requests)
+      {
+        id: recurring_booking.id,
+        total_sessions: recurring_booking.total_sessions,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        requests: requests.map { |r| request_summary_json(r) },
+        created_at: recurring_booking.created_at,
+        updated_at: recurring_booking.updated_at
+      }
+    end
   end
 end
diff --git a/app_charlie/app/models/recurring_booking.rb b/app_charlie/app/models/recurring_booking.rb
new file mode 100644
index 0000000..01d4ccf
--- /dev/null
+++ b/app_charlie/app/models/recurring_booking.rb
@@ -0,0 +1,13 @@
+class RecurringBooking < ApplicationRecord
+  include Paginatable
+
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :total_sessions, presence: true, numericality: { greater_than: 0 }
+
+  def fully_booked?
+    requests.count >= total_sessions
+  end
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
index 0000000..5f7dbc1
--- /dev/null
+++ b/app_charlie/app/services/requests/create_recurring_service.rb
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
+      return { success: false, errors: validation_errors } unless base_scheduled_at.present?
+
+      ActiveRecord::Base.transaction do
+        recurring_booking = RecurringBooking.create!(
+          client: @client,
+          provider: @provider,
+          total_sessions: TOTAL_SESSIONS
+        )
+
+        requests = TOTAL_SESSIONS.times.map do |week_offset|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: base_scheduled_at + week_offset.weeks,
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
+    def base_scheduled_at
+      @params[:scheduled_at]
+    end
+
+    def validation_errors
+      request = Request.new(
+        client: @client,
+        provider: @provider,
+        scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes],
+        amount_cents: @params[:amount_cents],
+        currency: @params[:currency] || "RUB"
+      )
+      request.validate
+      request.errors
+    end
+  end
+end
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..6c7e039 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :recurring
+      end
       member do
         patch :accept
         patch :decline
@@ -22,6 +25,8 @@
       resources :reviews, only: [:index, :create]
     end
 
+    resources :recurring_bookings, only: [:index, :show]
+
     resources :payments, only: [:index, :show]
   end
 
diff --git a/app_charlie/db/migrate/20260410083355_create_recurring_bookings.rb b/app_charlie/db/migrate/20260410083355_create_recurring_bookings.rb
new file mode 100644
index 0000000..5ca83db
--- /dev/null
+++ b/app_charlie/db/migrate/20260410083355_create_recurring_bookings.rb
@@ -0,0 +1,11 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.integer :total_sessions, default: 5, null: false
+
+      t.timestamps
+    end
+  end
+end
diff --git a/app_charlie/db/migrate/20260410083406_add_recurring_booking_to_requests.rb b/app_charlie/db/migrate/20260410083406_add_recurring_booking_to_requests.rb
new file mode 100644
index 0000000..7eef7bd
--- /dev/null
+++ b/app_charlie/db/migrate/20260410083406_add_recurring_booking_to_requests.rb
@@ -0,0 +1,5 @@
+class AddRecurringBookingToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_reference :requests, :recurring_booking, null: true, foreign_key: true
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..a360f78 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140805) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_083406) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -68,6 +68,16 @@
     t.index ["email"], name: "index_providers_on_email", unique: true
   end
 
+  create_table "recurring_bookings", force: :cascade do |t|
+    t.integer "client_id", null: false
+    t.datetime "created_at", null: false
+    t.integer "provider_id", null: false
+    t.integer "total_sessions", default: 5, null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "amount_cents", null: false
@@ -82,6 +92,7 @@
     t.string "location"
     t.text "notes"
     t.integer "provider_id", null: false
+    t.integer "recurring_booking_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
@@ -89,6 +100,7 @@
     t.datetime "updated_at", null: false
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_booking_id"], name: "index_requests_on_recurring_booking_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
   end
@@ -109,7 +121,10 @@
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
diff --git a/app_charlie/spec/factories/recurring_bookings.rb b/app_charlie/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..2796786
--- /dev/null
+++ b/app_charlie/spec/factories/recurring_bookings.rb
@@ -0,0 +1,7 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    total_sessions { 5 }
+  end
+end
diff --git a/app_charlie/spec/models/recurring_booking_spec.rb b/app_charlie/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..9850424
--- /dev/null
+++ b/app_charlie/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,34 @@
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
+
+    it "validates total_sessions is greater than 0" do
+      booking = build(:recurring_booking, total_sessions: 0)
+      expect(booking).not_to be_valid
+    end
+  end
+
+  describe "#fully_booked?" do
+    let(:recurring_booking) { create(:recurring_booking, total_sessions: 2) }
+
+    it "returns false when fewer requests than total_sessions" do
+      create(:request, recurring_booking: recurring_booking, client: recurring_booking.client, provider: recurring_booking.provider)
+      expect(recurring_booking.fully_booked?).to be false
+    end
+
+    it "returns true when requests equal total_sessions" do
+      2.times do
+        create(:request, recurring_booking: recurring_booking, client: recurring_booking.client, provider: recurring_booking.provider)
+      end
+      expect(recurring_booking.fully_booked?).to be true
+    end
+  end
+end
diff --git a/app_charlie/spec/services/requests/create_recurring_service_spec.rb b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..189eb37
--- /dev/null
+++ b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,109 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now }
+  let(:valid_params) do
+    {
+      scheduled_at: scheduled_at,
+      duration_minutes: 60,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 100_000,
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
+      it "sets total_sessions to 5" do
+        expect(result[:recurring_booking].total_sessions).to eq(5)
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
+        result[:requests].each do |request|
+          expect(request.recurring_booking).to eq(recurring_booking)
+        end
+      end
+
+      it "sets the same attributes on all requests" do
+        result[:requests].each do |request|
+          expect(request.duration_minutes).to eq(60)
+          expect(request.location).to eq("123 Main St")
+          expect(request.amount_cents).to eq(100_000)
+          expect(request.currency).to eq("RUB")
+          expect(request.client).to eq(client)
+          expect(request.provider).to eq(provider)
+        end
+      end
+
+      it "creates all requests in pending state" do
+        result[:requests].each do |request|
+          expect(request.state).to eq("pending")
+        end
+      end
+
+      it "notifies the provider about the recurring booking" do
+        result
+        log = read_notification_log
+        expect(log).to include("event=recurring_booking_created")
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
+        expect { result }.not_to change(Request, :count)
+        expect { result }.not_to change(RecurringBooking, :count)
+      end
+    end
+
+    context "with default currency" do
+      let(:valid_params) do
+        {
+          scheduled_at: scheduled_at,
+          duration_minutes: 60,
+          location: "123 Main St",
+          notes: "Weekly session",
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
