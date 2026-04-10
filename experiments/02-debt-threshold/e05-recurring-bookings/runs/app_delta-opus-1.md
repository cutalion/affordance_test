# Experiment: e05-recurring-bookings
# App: app_delta | Model: opus | Run: 1
# Branch: debt_experiment/e05-recurring-bookings/app_delta/opus/run-1

---

## Claude Output

All 197 tests pass (24 new + 173 existing). Here's what was implemented:

**Recurring Weekly Bookings Feature**

**Migration** — `recurring_bookings` table with client/provider refs, scheduling fields, amount, and state. Added `recurring_booking_id` foreign key to `orders`.

**Model** (`app/models/recurring_booking.rb`) — Belongs to client and provider, has many orders. Validates 5 sessions. Supports `cancel!` which cascels the booking and all its pending/confirmed orders.

**Service** (`app/services/recurring_bookings/create_service.rb`) — Creates the recurring booking and 5 orders scheduled one week apart (same day/time). Each order gets its own payment. Notifies the provider.

**API Controller** (`app/controllers/api/recurring_bookings_controller.rb`) — Endpoints:
- `GET /api/recurring_bookings` — list (scoped to current user)
- `GET /api/recurring_bookings/:id` — show (includes `order_ids`)
- `POST /api/recurring_bookings` — create (client only, params: `provider_id`, `scheduled_at`, `duration_minutes`, `location`, `notes`, `amount_cents`, `currency`)
- `PATCH /api/recurring_bookings/:id/cancel` — cancel (client only, cancels all pending orders)

**Tests** — 24 specs covering model validations, associations, scopes, cancellation logic, and the creation service (order count, weekly scheduling, payment creation, notifications).

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/recurring_bookings_controller.rb b/app_delta/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..e8f58a3
--- /dev/null
+++ b/app_delta/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,98 @@
+module Api
+  class RecurringBookingsController < BaseController
+    before_action :set_recurring_booking, only: [:show, :cancel]
+
+    def index
+      bookings = scoped_recurring_bookings.sorted.page(params[:page])
+      render json: bookings.map { |b| recurring_booking_summary_json(b) }
+    end
+
+    def show
+      render json: recurring_booking_detail_json(@recurring_booking)
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
+    def cancel
+      client = current_client!
+      return if performed?
+
+      unless @recurring_booking.client_id == client.id
+        return render_forbidden
+      end
+
+      @recurring_booking.cancel!
+      render json: recurring_booking_detail_json(@recurring_booking)
+    rescue RuntimeError => e
+      render json: { error: e.message }, status: :unprocessable_entity
+    end
+
+    private
+
+    def set_recurring_booking
+      @recurring_booking = RecurringBooking.find_by(id: params[:id])
+      render_not_found unless @recurring_booking
+    end
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
+    def recurring_booking_summary_json(booking)
+      {
+        id: booking.id,
+        state: booking.state,
+        starts_at: booking.starts_at,
+        session_count: booking.session_count,
+        client_id: booking.client_id,
+        provider_id: booking.provider_id
+      }
+    end
+
+    def recurring_booking_detail_json(booking)
+      {
+        id: booking.id,
+        state: booking.state,
+        starts_at: booking.starts_at,
+        duration_minutes: booking.duration_minutes,
+        location: booking.location,
+        notes: booking.notes,
+        session_count: booking.session_count,
+        amount_cents: booking.amount_cents,
+        currency: booking.currency,
+        canceled_at: booking.canceled_at,
+        client_id: booking.client_id,
+        provider_id: booking.provider_id,
+        order_ids: booking.orders.pluck(:id),
+        created_at: booking.created_at,
+        updated_at: booking.updated_at
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
index 0000000..d994e9e
--- /dev/null
+++ b/app_delta/app/models/recurring_booking.rb
@@ -0,0 +1,31 @@
+class RecurringBooking < ApplicationRecord
+  include Paginatable
+
+  belongs_to :client
+  belongs_to :provider
+  has_many :orders, dependent: :nullify
+
+  validates :starts_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :session_count, presence: true, numericality: { equal_to: 5 }
+  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
+  validates :currency, presence: true
+
+  scope :active, -> { where(state: "active") }
+  scope :canceled, -> { where(state: "canceled") }
+  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
+  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
+  scope :sorted, -> { order(starts_at: :desc) }
+
+  def cancel!
+    raise "Already canceled" if state == "canceled"
+
+    transaction do
+      update!(state: "canceled", canceled_at: Time.current)
+      orders.where(state: %w[pending confirmed]).find_each do |order|
+        order.update!(cancel_reason: "Recurring booking canceled")
+        order.cancel!
+      end
+    end
+  end
+end
diff --git a/app_delta/app/services/recurring_bookings/create_service.rb b/app_delta/app/services/recurring_bookings/create_service.rb
new file mode 100644
index 0000000..09450d5
--- /dev/null
+++ b/app_delta/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,62 @@
+module RecurringBookings
+  class CreateService
+    SESSIONS = 5
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
+        starts_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes],
+        location: @params[:location],
+        notes: @params[:notes],
+        session_count: SESSIONS,
+        amount_cents: @params[:amount_cents],
+        currency: @params[:currency] || "RUB"
+      )
+
+      RecurringBooking.transaction do
+        recurring_booking.save!
+
+        SESSIONS.times do |i|
+          scheduled_at = Time.parse(@params[:scheduled_at].to_s) + i.weeks
+
+          Orders::CreateService.new(
+            client: @client,
+            provider: @provider,
+            params: {
+              scheduled_at: scheduled_at,
+              duration_minutes: @params[:duration_minutes],
+              location: @params[:location],
+              notes: @params[:notes],
+              amount_cents: @params[:amount_cents],
+              currency: @params[:currency] || "RUB"
+            }
+          ).call.tap do |result|
+            unless result[:success]
+              raise ActiveRecord::Rollback
+            end
+            result[:order].update!(recurring_booking: recurring_booking)
+          end
+        end
+      end
+
+      NotificationService.notify(
+        @provider,
+        :recurring_booking_created,
+        recurring_booking_id: recurring_booking.id,
+        session_count: SESSIONS
+      )
+
+      { success: true, recurring_booking: recurring_booking }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/app_delta/config/routes.rb b/app_delta/config/routes.rb
index d9e099b..7b74eec 100644
--- a/app_delta/config/routes.rb
+++ b/app_delta/config/routes.rb
@@ -28,6 +28,12 @@
       resources :reviews, only: [:index, :create]
     end
 
+    resources :recurring_bookings, only: [:index, :show, :create] do
+      member do
+        patch :cancel
+      end
+    end
+
     resources :payments, only: [:index, :show]
 
     resources :announcements, only: [:index, :show, :create] do
diff --git a/app_delta/db/migrate/20260410083744_create_recurring_bookings.rb b/app_delta/db/migrate/20260410083744_create_recurring_bookings.rb
new file mode 100644
index 0000000..814c302
--- /dev/null
+++ b/app_delta/db/migrate/20260410083744_create_recurring_bookings.rb
@@ -0,0 +1,23 @@
+class CreateRecurringBookings < ActiveRecord::Migration[8.1]
+  def change
+    create_table :recurring_bookings do |t|
+      t.references :client, null: false, foreign_key: true
+      t.references :provider, null: false, foreign_key: true
+      t.datetime :starts_at, null: false
+      t.integer :duration_minutes, null: false
+      t.string :location
+      t.text :notes
+      t.integer :session_count, null: false, default: 5
+      t.integer :amount_cents, null: false
+      t.string :currency, null: false, default: "RUB"
+      t.string :state, null: false, default: "active"
+      t.datetime :canceled_at
+
+      t.timestamps
+    end
+
+    add_index :recurring_bookings, :state
+
+    add_reference :orders, :recurring_booking, null: true, foreign_key: true
+  end
+end
diff --git a/app_delta/db/schema.rb b/app_delta/db/schema.rb
index c5b443e..9bdc3bb 100644
--- a/app_delta/db/schema.rb
+++ b/app_delta/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_083744) do
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
@@ -110,6 +112,25 @@
     t.index ["email"], name: "index_providers_on_email", unique: true
   end
 
+  create_table "recurring_bookings", force: :cascade do |t|
+    t.integer "amount_cents", null: false
+    t.datetime "canceled_at"
+    t.integer "client_id", null: false
+    t.datetime "created_at", null: false
+    t.string "currency", default: "RUB", null: false
+    t.integer "duration_minutes", null: false
+    t.string "location"
+    t.text "notes"
+    t.integer "provider_id", null: false
+    t.integer "session_count", default: 5, null: false
+    t.datetime "starts_at", null: false
+    t.string "state", default: "active", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_recurring_bookings_on_client_id"
+    t.index ["provider_id"], name: "index_recurring_bookings_on_provider_id"
+    t.index ["state"], name: "index_recurring_bookings_on_state"
+  end
+
   create_table "requests", force: :cascade do |t|
     t.datetime "accepted_at"
     t.integer "client_id", null: false
@@ -160,9 +181,12 @@
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
index 0000000..74a0029
--- /dev/null
+++ b/app_delta/spec/factories/recurring_bookings.rb
@@ -0,0 +1,18 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    starts_at { 3.days.from_now }
+    duration_minutes { 120 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+    session_count { 5 }
+    amount_cents { 350_000 }
+    currency { "RUB" }
+
+    trait :canceled do
+      state { "canceled" }
+      canceled_at { Time.current }
+    end
+  end
+end
diff --git a/app_delta/spec/models/recurring_booking_spec.rb b/app_delta/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..a8c2b96
--- /dev/null
+++ b/app_delta/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,80 @@
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
+    it { is_expected.to validate_presence_of(:starts_at) }
+    it { is_expected.to validate_presence_of(:duration_minutes) }
+    it { is_expected.to validate_presence_of(:amount_cents) }
+    it { is_expected.to validate_presence_of(:currency) }
+
+    it "validates duration_minutes is greater than 0" do
+      booking = build(:recurring_booking, duration_minutes: 0)
+      expect(booking).not_to be_valid
+    end
+
+    it "validates session_count is 5" do
+      booking = build(:recurring_booking, session_count: 3)
+      expect(booking).not_to be_valid
+    end
+  end
+
+  describe "#cancel!" do
+    let(:recurring_booking) { create(:recurring_booking) }
+
+    it "sets state to canceled" do
+      recurring_booking.cancel!
+      expect(recurring_booking.reload.state).to eq("canceled")
+    end
+
+    it "sets canceled_at" do
+      freeze_time do
+        recurring_booking.cancel!
+        expect(recurring_booking.reload.canceled_at).to be_within(1.second).of(Time.current)
+      end
+    end
+
+    it "cancels pending orders" do
+      order = create(:order, recurring_booking: recurring_booking, client: recurring_booking.client, provider: recurring_booking.provider)
+      recurring_booking.cancel!
+      expect(order.reload.state).to eq("canceled")
+    end
+
+    it "does not cancel completed orders" do
+      order = create(:order, :completed, recurring_booking: recurring_booking, client: recurring_booking.client, provider: recurring_booking.provider)
+      recurring_booking.cancel!
+      expect(order.reload.state).to eq("completed")
+    end
+
+    it "raises if already canceled" do
+      recurring_booking.cancel!
+      expect { recurring_booking.cancel! }.to raise_error(RuntimeError, "Already canceled")
+    end
+  end
+
+  describe "scopes" do
+    let!(:active_booking) { create(:recurring_booking) }
+    let!(:canceled_booking) { create(:recurring_booking, :canceled) }
+
+    describe ".active" do
+      it "returns only active bookings" do
+        expect(RecurringBooking.active).to include(active_booking)
+        expect(RecurringBooking.active).not_to include(canceled_booking)
+      end
+    end
+
+    describe ".canceled" do
+      it "returns only canceled bookings" do
+        expect(RecurringBooking.canceled).to include(canceled_booking)
+        expect(RecurringBooking.canceled).not_to include(active_booking)
+      end
+    end
+  end
+end
diff --git a/app_delta/spec/services/recurring_bookings/create_service_spec.rb b/app_delta/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..d4819fc
--- /dev/null
+++ b/app_delta/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,71 @@
+require "rails_helper"
+
+RSpec.describe RecurringBookings::CreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now.beginning_of_hour }
+  let(:valid_params) do
+    {
+      scheduled_at: scheduled_at,
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
+      it "creates 5 orders" do
+        expect { result }.to change(Order, :count).by(5)
+      end
+
+      it "creates 5 payments" do
+        expect { result }.to change(Payment, :count).by(5)
+      end
+
+      it "schedules orders one week apart" do
+        result
+        booking = result[:recurring_booking]
+        orders = booking.orders.order(:scheduled_at)
+
+        5.times do |i|
+          expected_time = scheduled_at + i.weeks
+          expect(orders[i].scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "associates all orders with the recurring booking" do
+        result
+        booking = result[:recurring_booking]
+        expect(booking.orders.count).to eq(5)
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=recurring_booking_created")
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: nil, amount_cents: nil } }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "does not create any orders" do
+        expect { result }.not_to change(Order, :count)
+      end
+    end
+  end
+end
```
