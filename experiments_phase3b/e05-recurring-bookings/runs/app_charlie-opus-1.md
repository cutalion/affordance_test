# Experiment: e05-recurring-bookings
# App: app_charlie | Model: opus | Run: 1
# Branch: debt_experiment/e05-recurring-bookings/app_charlie/opus/run-1

---

## Claude Output

Here's what was implemented:

**New files:**
- `db/migrate/..._create_recurring_bookings.rb` - `recurring_bookings` table + `recurring_booking_id` FK on `requests`
- `app/models/recurring_booking.rb` - model with validations, associations, and `#scheduled_dates` helper
- `app/services/recurring_bookings/create_service.rb` - creates a `RecurringBooking` + 5 weekly `Request` records in a transaction
- `app/controllers/api/recurring_bookings_controller.rb` - `index`, `show`, `create` endpoints
- `spec/models/recurring_booking_spec.rb` - model specs
- `spec/services/recurring_bookings/create_service_spec.rb` - service specs
- `spec/factories/recurring_bookings.rb` - factory

**Modified files:**
- `Request` - added `belongs_to :recurring_booking, optional: true`
- `Client` / `Provider` - added `has_many :recurring_bookings`
- `config/routes.rb` - added `resources :recurring_bookings, only: [:index, :show, :create]`

**How it works:** A client POSTs to `/api/recurring_bookings` with `provider_id`, `scheduled_at` (first session time), `duration_minutes`, `amount_cents`, etc. The service creates a `RecurringBooking` record and 5 individual `Request` records spaced 1 week apart, all in a transaction. Each request follows its normal state machine independently. The provider is notified of the recurring booking creation.

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/recurring_bookings_controller.rb b/app_charlie/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..420c376
--- /dev/null
+++ b/app_charlie/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,91 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      client = current_client!
+      return if performed?
+
+      recurring_bookings = client.recurring_bookings.order(created_at: :desc).page(params[:page])
+      render json: recurring_bookings.map { |rb| recurring_booking_summary_json(rb) }
+    end
+
+    def show
+      recurring_booking = RecurringBooking.find_by(id: params[:id])
+      return render_not_found unless recurring_booking
+      return render_forbidden unless owns_recurring_booking?(recurring_booking)
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
+    def owns_recurring_booking?(recurring_booking)
+      if current_user.is_a?(Client)
+        recurring_booking.client_id == current_user.id
+      else
+        recurring_booking.provider_id == current_user.id
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
+        starts_at: recurring_booking.starts_at,
+        sessions_count: recurring_booking.sessions_count,
+        amount_cents: recurring_booking.amount_cents,
+        currency: recurring_booking.currency,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        created_at: recurring_booking.created_at
+      }
+    end
+
+    def recurring_booking_detail_json(recurring_booking)
+      {
+        id: recurring_booking.id,
+        starts_at: recurring_booking.starts_at,
+        duration_minutes: recurring_booking.duration_minutes,
+        location: recurring_booking.location,
+        notes: recurring_booking.notes,
+        sessions_count: recurring_booking.sessions_count,
+        amount_cents: recurring_booking.amount_cents,
+        currency: recurring_booking.currency,
+        client_id: recurring_booking.client_id,
+        provider_id: recurring_booking.provider_id,
+        requests: recurring_booking.requests.sorted.map do |r|
+          {
+            id: r.id,
+            state: r.state,
+            scheduled_at: r.scheduled_at,
+            amount_cents: r.amount_cents
+          }
+        end,
+        created_at: recurring_booking.created_at,
+        updated_at: recurring_booking.updated_at
+      }
+    end
+  end
+end
diff --git a/app_charlie/app/models/client.rb b/app_charlie/app/models/client.rb
index 264034b..6ee534f 100644
--- a/app_charlie/app/models/client.rb
+++ b/app_charlie/app/models/client.rb
@@ -2,6 +2,7 @@ class Client < ApplicationRecord
   serialize :notification_preferences, coder: JSON
 
   has_many :requests, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
   has_many :cards, dependent: :destroy
 
   validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
diff --git a/app_charlie/app/models/provider.rb b/app_charlie/app/models/provider.rb
index b093865..9d460ba 100644
--- a/app_charlie/app/models/provider.rb
+++ b/app_charlie/app/models/provider.rb
@@ -2,6 +2,7 @@ class Provider < ApplicationRecord
   serialize :notification_preferences, coder: JSON
 
   has_many :requests, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
 
   validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
   validates :name, presence: true
diff --git a/app_charlie/app/models/recurring_booking.rb b/app_charlie/app/models/recurring_booking.rb
new file mode 100644
index 0000000..030e79a
--- /dev/null
+++ b/app_charlie/app/models/recurring_booking.rb
@@ -0,0 +1,15 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :starts_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
+  validates :currency, presence: true
+  validates :sessions_count, presence: true, numericality: { greater_than: 0 }
+
+  def scheduled_dates
+    (0...sessions_count).map { |i| starts_at + i.weeks }
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
 
diff --git a/app_charlie/app/services/recurring_bookings/create_service.rb b/app_charlie/app/services/recurring_bookings/create_service.rb
new file mode 100644
index 0000000..232a26f
--- /dev/null
+++ b/app_charlie/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,52 @@
+module RecurringBookings
+  class CreateService
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
+          provider: @provider,
+          starts_at: @params[:scheduled_at],
+          duration_minutes: @params[:duration_minutes],
+          location: @params[:location],
+          notes: @params[:notes],
+          amount_cents: @params[:amount_cents],
+          currency: @params[:currency] || "RUB",
+          sessions_count: SESSIONS_COUNT
+        )
+
+        requests = recurring_booking.scheduled_dates.map do |date|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: date,
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
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..0672c8b 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -22,6 +22,8 @@
       resources :reviews, only: [:index, :create]
     end
 
+    resources :recurring_bookings, only: [:index, :show, :create]
+
     resources :payments, only: [:index, :show]
   end
 
diff --git a/app_charlie/db/migrate/20260409192754_create_recurring_bookings.rb b/app_charlie/db/migrate/20260409192754_create_recurring_bookings.rb
new file mode 100644
index 0000000..f24a521
--- /dev/null
+++ b/app_charlie/db/migrate/20260409192754_create_recurring_bookings.rb
@@ -0,0 +1,19 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.integer :sessions_count, null: false, default: 5
+      t.datetime :starts_at, null: false
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
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 4757a0b..b556160 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_09_081113) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_09_192754) do
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
diff --git a/app_charlie/spec/factories/recurring_bookings.rb b/app_charlie/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..11dd819
--- /dev/null
+++ b/app_charlie/spec/factories/recurring_bookings.rb
@@ -0,0 +1,13 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    starts_at { 3.days.from_now }
+    duration_minutes { 120 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+    amount_cents { 350_000 }
+    currency { "RUB" }
+    sessions_count { 5 }
+  end
+end
diff --git a/app_charlie/spec/models/recurring_booking_spec.rb b/app_charlie/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..acf7257
--- /dev/null
+++ b/app_charlie/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,39 @@
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
+    subject { build(:recurring_booking) }
+
+    it { is_expected.to validate_presence_of(:starts_at) }
+    it { is_expected.to validate_presence_of(:duration_minutes) }
+    it { is_expected.to validate_presence_of(:amount_cents) }
+    it { is_expected.to validate_presence_of(:currency) }
+    it { is_expected.to validate_presence_of(:sessions_count) }
+
+    it "validates duration_minutes is greater than 0" do
+      recurring_booking = build(:recurring_booking, duration_minutes: 0)
+      expect(recurring_booking).not_to be_valid
+    end
+  end
+
+  describe "#scheduled_dates" do
+    it "returns 5 weekly dates starting from starts_at" do
+      starts_at = Time.zone.parse("2026-04-13 10:00:00")
+      recurring_booking = build(:recurring_booking, starts_at: starts_at, sessions_count: 5)
+
+      dates = recurring_booking.scheduled_dates
+      expect(dates.length).to eq(5)
+      expect(dates[0]).to eq(starts_at)
+      expect(dates[1]).to eq(starts_at + 1.week)
+      expect(dates[2]).to eq(starts_at + 2.weeks)
+      expect(dates[3]).to eq(starts_at + 3.weeks)
+      expect(dates[4]).to eq(starts_at + 4.weeks)
+    end
+  end
+end
diff --git a/app_charlie/spec/services/recurring_bookings/create_service_spec.rb b/app_charlie/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..34b638a
--- /dev/null
+++ b/app_charlie/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,79 @@
+require "rails_helper"
+
+RSpec.describe RecurringBookings::CreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:valid_params) do
+    {
+      scheduled_at: 3.days.from_now,
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
+      it "creates a recurring booking" do
+        expect { result }.to change(RecurringBooking, :count).by(1)
+        expect(result[:success]).to be true
+      end
+
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+
+      it "creates requests scheduled weekly apart" do
+        requests = result[:requests].sort_by(&:scheduled_at)
+        (0..3).each do |i|
+          diff = requests[i + 1].scheduled_at - requests[i].scheduled_at
+          expect(diff).to be_within(1.second).of(1.week)
+        end
+      end
+
+      it "links all requests to the recurring booking" do
+        recurring_booking = result[:recurring_booking]
+        expect(recurring_booking.requests.count).to eq(5)
+        result[:requests].each do |request|
+          expect(request.recurring_booking).to eq(recurring_booking)
+        end
+      end
+
+      it "sets same amount on all requests" do
+        result[:requests].each do |request|
+          expect(request.amount_cents).to eq(350_000)
+          expect(request.currency).to eq("RUB")
+        end
+      end
+
+      it "creates all requests in pending state" do
+        result[:requests].each do |request|
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
+  end
+end
```
