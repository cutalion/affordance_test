# Experiment: e05-recurring-bookings
# App: app_delta | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_delta/opus/run-3

---

## Claude Output

All 192 tests pass (0 failures). Here's what was implemented:

**Database:**
- New `recurring_bookings` table with `client_id`, `provider_id`, `start_at`, `duration_minutes`, `amount_cents`, `currency`, `location`, `notes`, `sessions_count`
- Added `recurring_booking_id` foreign key to `orders`

**Models:**
- `RecurringBooking` — belongs to client and provider, has many orders. Validates sessions_count is exactly 5.
- `Order` — added optional `belongs_to :recurring_booking`
- `Client` / `Provider` — added `has_many :recurring_bookings`

**Service:**
- `RecurringBookings::CreateService` — creates the recurring booking and 5 orders (each 1 week apart) with payments in a single transaction. Notifies the provider for each order.

**API:**
- `POST /api/recurring_bookings` — creates a recurring booking (client-only)
- `GET /api/recurring_bookings` — lists client's recurring bookings
- `GET /api/recurring_bookings/:id` — shows detail including all orders

**Tests:**
- Model spec for `RecurringBooking` (associations, validations)
- Service spec for `RecurringBookings::CreateService` (creates 5 orders, 5 payments, weekly scheduling, notifications, transactional rollback on invalid params)

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/recurring_bookings_controller.rb b/app_delta/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..04c0d1b
--- /dev/null
+++ b/app_delta/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,82 @@
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
+    def recurring_booking_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
+    end
+
+    def recurring_booking_summary_json(rb)
+      {
+        id: rb.id,
+        provider_id: rb.provider_id,
+        start_at: rb.start_at,
+        duration_minutes: rb.duration_minutes,
+        amount_cents: rb.amount_cents,
+        currency: rb.currency,
+        sessions_count: rb.sessions_count,
+        created_at: rb.created_at
+      }
+    end
+
+    def recurring_booking_detail_json(rb)
+      {
+        id: rb.id,
+        client_id: rb.client_id,
+        provider_id: rb.provider_id,
+        start_at: rb.start_at,
+        duration_minutes: rb.duration_minutes,
+        location: rb.location,
+        notes: rb.notes,
+        amount_cents: rb.amount_cents,
+        currency: rb.currency,
+        sessions_count: rb.sessions_count,
+        orders: rb.orders.sorted.map do |order|
+          {
+            id: order.id,
+            state: order.state,
+            scheduled_at: order.scheduled_at,
+            amount_cents: order.amount_cents
+          }
+        end,
+        created_at: rb.created_at,
+        updated_at: rb.updated_at
+      }
+    end
+  end
+end
diff --git a/app_delta/app/models/client.rb b/app_delta/app/models/client.rb
index d5d4a1b..8db1201 100644
--- a/app_delta/app/models/client.rb
+++ b/app_delta/app/models/client.rb
@@ -3,6 +3,7 @@ class Client < ApplicationRecord
 
   has_many :requests, dependent: :destroy
   has_many :orders, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
   has_many :announcements, dependent: :destroy
   has_many :cards, dependent: :destroy
   has_many :reviews, as: :author, dependent: :destroy
diff --git a/app_delta/app/models/order.rb b/app_delta/app/models/order.rb
index 0fc2547..487f1e8 100644
--- a/app_delta/app/models/order.rb
+++ b/app_delta/app/models/order.rb
@@ -3,6 +3,7 @@ class Order < ApplicationRecord
   include Paginatable
 
   belongs_to :request, optional: true
+  belongs_to :recurring_booking, optional: true
   belongs_to :client
   belongs_to :provider
   has_one :payment, dependent: :destroy
diff --git a/app_delta/app/models/provider.rb b/app_delta/app/models/provider.rb
index 412d8fc..f7fbe53 100644
--- a/app_delta/app/models/provider.rb
+++ b/app_delta/app/models/provider.rb
@@ -3,6 +3,7 @@ class Provider < ApplicationRecord
 
   has_many :requests, dependent: :destroy
   has_many :orders, dependent: :destroy
+  has_many :recurring_bookings, dependent: :destroy
   has_many :responses, dependent: :destroy
   has_many :reviews, as: :author, dependent: :destroy
 
diff --git a/app_delta/app/models/recurring_booking.rb b/app_delta/app/models/recurring_booking.rb
new file mode 100644
index 0000000..abdd156
--- /dev/null
+++ b/app_delta/app/models/recurring_booking.rb
@@ -0,0 +1,11 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :orders, dependent: :nullify
+
+  validates :start_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
+  validates :currency, presence: true
+  validates :sessions_count, presence: true, numericality: { equal_to: 5 }
+end
diff --git a/app_delta/app/services/recurring_bookings/create_service.rb b/app_delta/app/services/recurring_bookings/create_service.rb
new file mode 100644
index 0000000..95b7ada
--- /dev/null
+++ b/app_delta/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,68 @@
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
+      recurring_booking = RecurringBooking.new(
+        client: @client,
+        provider: @provider,
+        start_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes],
+        location: @params[:location],
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents],
+        currency: @params[:currency] || "RUB",
+        sessions_count: SESSIONS_COUNT
+      )
+
+      orders = []
+
+      RecurringBooking.transaction do
+        recurring_booking.save!
+
+        SESSIONS_COUNT.times do |i|
+          scheduled_at = recurring_booking.start_at + i.weeks
+          order = Order.create!(
+            recurring_booking: recurring_booking,
+            client: @client,
+            provider: @provider,
+            scheduled_at: scheduled_at,
+            duration_minutes: recurring_booking.duration_minutes,
+            location: recurring_booking.location,
+            notes: recurring_booking.notes,
+            amount_cents: recurring_booking.amount_cents,
+            currency: recurring_booking.currency
+          )
+          Payment.create!(
+            order: order,
+            amount_cents: order.amount_cents,
+            currency: order.currency,
+            fee_cents: calculate_fee(order.amount_cents),
+            status: "pending"
+          )
+          orders << order
+        end
+      end
+
+      orders.each do |order|
+        NotificationService.notify(@provider, :order_created, order_id: order.id)
+      end
+
+      { success: true, recurring_booking: recurring_booking, orders: orders }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+
+    private
+
+    def calculate_fee(amount_cents)
+      (amount_cents * 0.1).to_i
+    end
+  end
+end
diff --git a/app_delta/config/routes.rb b/app_delta/config/routes.rb
index d9e099b..5e74971 100644
--- a/app_delta/config/routes.rb
+++ b/app_delta/config/routes.rb
@@ -28,6 +28,8 @@
       resources :reviews, only: [:index, :create]
     end
 
+    resources :recurring_bookings, only: [:index, :show, :create]
+
     resources :payments, only: [:index, :show]
 
     resources :announcements, only: [:index, :show, :create] do
diff --git a/app_delta/db/migrate/20260410120000_create_recurring_bookings.rb b/app_delta/db/migrate/20260410120000_create_recurring_bookings.rb
new file mode 100644
index 0000000..aab1edb
--- /dev/null
+++ b/app_delta/db/migrate/20260410120000_create_recurring_bookings.rb
@@ -0,0 +1,19 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.datetime :start_at, null: false
+      t.integer :duration_minutes, null: false
+      t.integer :amount_cents, null: false
+      t.string :currency, null: false, default: "RUB"
+      t.string :location
+      t.text :notes
+      t.integer :sessions_count, null: false, default: 5
+
+      t.timestamps
+    end
+
+    add_reference :orders, :recurring_booking, foreign_key: true
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index c5b443e..9282e51 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_120000) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -65,6 +65,7 @@
     t.string "location"
     t.text "notes"
     t.integer "provider_id", null: false
+    t.integer "recurring_booking_id"
     t.text "reject_reason"
     t.integer "request_id"
     t.datetime "scheduled_at", null: false
@@ -73,6 +74,7 @@
     t.datetime "updated_at", null: false
     t.index ["client_id"], name: "index_orders_on_client_id"
     t.index ["provider_id"], name: "index_orders_on_provider_id"
+    t.index ["recurring_booking_id"], name: "index_orders_on_recurring_booking_id"
     t.index ["request_id"], name: "index_orders_on_request_id"
     t.index ["scheduled_at"], name: "index_orders_on_scheduled_at"
     t.index ["state"], name: "index_orders_on_state"
@@ -110,6 +112,22 @@
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
+    t.datetime "start_at", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "client_id", null: false
@@ -160,9 +178,12 @@
   add_foreign_key "cards", "clients"
   add_foreign_key "orders", "clients"
   add_foreign_key "orders", "providers"
+  add_foreign_key "orders", "recurring_bookings"
   add_foreign_key "orders", "requests"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "orders"
+  add_foreign_key "recurring_bookings", "clients"
+  add_foreign_key "recurring_bookings", "providers"
   add_foreign_key "requests", "clients"
   add_foreign_key "requests", "providers"
   add_foreign_key "responses", "announcements"
diff --git a/app_delta/spec/factories/recurring_bookings.rb b/app_delta/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..00e6970
--- /dev/null
+++ b/app_delta/spec/factories/recurring_bookings.rb
@@ -0,0 +1,13 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    start_at { 3.days.from_now }
+    duration_minutes { 120 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+    amount_cents { 350_000 }
+    currency { "RUB" }
+    sessions_count { 5 }
+  end
+end
diff --git a/app_delta/spec/models/recurring_booking_spec.rb b/app_delta/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..99405c1
--- /dev/null
+++ b/app_delta/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,39 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking, type: :model do
+  describe "associations" do
+    it { is_expected.to belong_to(:client) }
+    it { is_expected.to belong_to(:provider) }
+    it { is_expected.to have_many(:orders).dependent(:nullify) }
+  end
+
+  describe "validations" do
+    subject { build(:recurring_booking) }
+
+    it { is_expected.to validate_presence_of(:start_at) }
+    it { is_expected.to validate_presence_of(:duration_minutes) }
+    it { is_expected.to validate_presence_of(:amount_cents) }
+    it { is_expected.to validate_presence_of(:currency) }
+    it { is_expected.to validate_presence_of(:sessions_count) }
+
+    it "validates duration_minutes is greater than 0" do
+      rb = build(:recurring_booking, duration_minutes: 0)
+      expect(rb).not_to be_valid
+      expect(rb.errors[:duration_minutes]).to be_present
+    end
+
+    it "validates amount_cents is >= 0" do
+      rb = build(:recurring_booking, amount_cents: -1)
+      expect(rb).not_to be_valid
+
+      rb.amount_cents = 0
+      expect(rb).to be_valid
+    end
+
+    it "validates sessions_count is exactly 5" do
+      rb = build(:recurring_booking, sessions_count: 3)
+      expect(rb).not_to be_valid
+      expect(rb.errors[:sessions_count]).to be_present
+    end
+  end
+end
diff --git a/app_delta/spec/services/recurring_bookings/create_service_spec.rb b/app_delta/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..10e7d51
--- /dev/null
+++ b/app_delta/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,83 @@
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
+        expect(result[:recurring_booking]).to be_persisted
+        expect(result[:recurring_booking].sessions_count).to eq(5)
+      end
+
+      it "creates 5 orders" do
+        expect { result }.to change(Order, :count).by(5)
+        expect(result[:orders].size).to eq(5)
+      end
+
+      it "creates 5 payments with 10% fee" do
+        expect { result }.to change(Payment, :count).by(5)
+        result[:orders].each do |order|
+          payment = order.payment
+          expect(payment.status).to eq("pending")
+          expect(payment.fee_cents).to eq(35_000)
+          expect(payment.amount_cents).to eq(350_000)
+        end
+      end
+
+      it "schedules orders one week apart" do
+        orders = result[:orders]
+        start_time = orders.first.scheduled_at
+
+        orders.each_with_index do |order, i|
+          expected_time = start_time + i.weeks
+          expect(order.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "associates all orders with the recurring booking" do
+        recurring_booking = result[:recurring_booking]
+        result[:orders].each do |order|
+          expect(order.recurring_booking).to eq(recurring_booking)
+        end
+      end
+
+      it "notifies the provider for each order" do
+        clear_notification_log
+        result
+        log = read_notification_log
+        # 5 orders × 3 channels (push, sms, email) = 15
+        expect(log.scan("event=order_created").count).to eq(15)
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil, currency: nil } }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "does not create any records" do
+        expect { result }.not_to change(RecurringBooking, :count)
+        expect { result }.not_to change(Order, :count)
+      end
+    end
+  end
+end
```
