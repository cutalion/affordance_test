# Experiment: e05-recurring-bookings
# App: app_delta | Model: opus | Run: 2
# Branch: debt_experiment/e05-recurring-bookings/app_delta/opus/run-2

---

## Claude Output

All 186 specs pass (13 new + 173 existing). Here's what was implemented:

**New files:**
- `app/models/recurring_booking.rb` — Model with validations, scopes, and associations
- `app/services/recurring_bookings/create_service.rb` — Creates a RecurringBooking + 5 weekly orders with payments in a single transaction
- `app/controllers/api/recurring_bookings_controller.rb` — API endpoints (index/show/create)
- `spec/models/recurring_booking_spec.rb` — Model validation/association specs
- `spec/services/recurring_bookings/create_service_spec.rb` — Service specs covering order creation, payments, notifications, and error handling
- `spec/factories/recurring_bookings.rb` — Factory

**Modified files:**
- `app/models/order.rb` — Added `belongs_to :recurring_booking, optional: true`
- `config/routes.rb` — Added `resources :recurring_bookings, only: [:index, :show, :create]`

**API:**
- `POST /api/recurring_bookings` — Client creates a recurring booking (params: `provider_id`, `scheduled_at`, `duration_minutes`, `amount_cents`, `location`, `notes`, `currency`). Creates 5 orders at weekly intervals with payments.
- `GET /api/recurring_bookings` — List recurring bookings for the authenticated user
- `GET /api/recurring_bookings/:id` — Show details including all child orders

---

## Git Diff

```diff
diff --git a/app_delta/app/controllers/api/recurring_bookings_controller.rb b/app_delta/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..3462686
--- /dev/null
+++ b/app_delta/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,89 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      recurring_bookings = scoped_recurring_bookings.sorted.page(params[:page])
+      render json: recurring_bookings.map { |rb| summary_json(rb) }
+    end
+
+    def show
+      recurring_booking = RecurringBooking.find_by(id: params[:id])
+      return render_not_found unless recurring_booking
+
+      render json: detail_json(recurring_booking)
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
+        render json: detail_json(result[:recurring_booking]), status: :created
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
+    def summary_json(rb)
+      {
+        id: rb.id,
+        first_scheduled_at: rb.first_scheduled_at,
+        session_count: rb.session_count,
+        amount_cents: rb.amount_cents,
+        currency: rb.currency,
+        client_id: rb.client_id,
+        provider_id: rb.provider_id
+      }
+    end
+
+    def detail_json(rb)
+      {
+        id: rb.id,
+        first_scheduled_at: rb.first_scheduled_at,
+        session_count: rb.session_count,
+        duration_minutes: rb.duration_minutes,
+        location: rb.location,
+        notes: rb.notes,
+        amount_cents: rb.amount_cents,
+        currency: rb.currency,
+        client_id: rb.client_id,
+        provider_id: rb.provider_id,
+        orders: rb.orders.sorted.map { |o| order_json(o) },
+        created_at: rb.created_at,
+        updated_at: rb.updated_at
+      }
+    end
+
+    def order_json(order)
+      {
+        id: order.id,
+        state: order.state,
+        scheduled_at: order.scheduled_at,
+        amount_cents: order.amount_cents,
+        currency: order.currency
+      }
+    end
+  end
+end
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
diff --git a/app_delta/app/models/recurring_booking.rb b/app_delta/app/models/recurring_booking.rb
new file mode 100644
index 0000000..0b385b0
--- /dev/null
+++ b/app_delta/app/models/recurring_booking.rb
@@ -0,0 +1,15 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :orders, dependent: :destroy
+
+  validates :first_scheduled_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
+  validates :currency, presence: true
+  validates :session_count, presence: true, numericality: { greater_than: 0 }
+
+  scope :by_client, ->(client_id) { where(client_id: client_id) if client_id.present? }
+  scope :by_provider, ->(provider_id) { where(provider_id: provider_id) if provider_id.present? }
+  scope :sorted, -> { order(created_at: :desc) }
+end
diff --git a/app_delta/app/services/recurring_bookings/create_service.rb b/app_delta/app/services/recurring_bookings/create_service.rb
new file mode 100644
index 0000000..7b4c887
--- /dev/null
+++ b/app_delta/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,68 @@
+module RecurringBookings
+  class CreateService
+    SESSION_COUNT = 5
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
+        first_scheduled_at: @params[:scheduled_at],
+        duration_minutes: @params[:duration_minutes],
+        location: @params[:location],
+        notes: @params[:notes],
+        amount_cents: @params[:amount_cents],
+        currency: @params[:currency] || "RUB",
+        session_count: SESSION_COUNT
+      )
+
+      RecurringBooking.transaction do
+        recurring_booking.save!
+
+        SESSION_COUNT.times do |i|
+          scheduled_at = recurring_booking.first_scheduled_at + i.weeks
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
+        end
+      end
+
+      NotificationService.notify(
+        @provider,
+        :recurring_booking_created,
+        recurring_booking_id: recurring_booking.id,
+        session_count: SESSION_COUNT
+      )
+
+      { success: true, recurring_booking: recurring_booking }
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
diff --git a/app_delta/spec/factories/recurring_bookings.rb b/app_delta/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..8b9f731
--- /dev/null
+++ b/app_delta/spec/factories/recurring_bookings.rb
@@ -0,0 +1,13 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    first_scheduled_at { 3.days.from_now }
+    duration_minutes { 120 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+    amount_cents { 350_000 }
+    currency { "RUB" }
+    session_count { 5 }
+  end
+end
diff --git a/app_delta/spec/models/recurring_booking_spec.rb b/app_delta/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..4d729de
--- /dev/null
+++ b/app_delta/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,38 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking do
+  describe "validations" do
+    it "is valid with valid attributes" do
+      recurring_booking = build(:recurring_booking)
+      expect(recurring_booking).to be_valid
+    end
+
+    it "requires first_scheduled_at" do
+      recurring_booking = build(:recurring_booking, first_scheduled_at: nil)
+      expect(recurring_booking).not_to be_valid
+    end
+
+    it "requires duration_minutes greater than 0" do
+      recurring_booking = build(:recurring_booking, duration_minutes: 0)
+      expect(recurring_booking).not_to be_valid
+    end
+
+    it "requires amount_cents" do
+      recurring_booking = build(:recurring_booking, amount_cents: nil)
+      expect(recurring_booking).not_to be_valid
+    end
+
+    it "requires currency" do
+      recurring_booking = build(:recurring_booking, currency: nil)
+      expect(recurring_booking).not_to be_valid
+    end
+  end
+
+  describe "associations" do
+    it "has many orders" do
+      recurring_booking = create(:recurring_booking)
+      order = create(:order, recurring_booking: recurring_booking, client: recurring_booking.client, provider: recurring_booking.provider)
+      expect(recurring_booking.orders).to include(order)
+    end
+  end
+end
diff --git a/app_delta/spec/services/recurring_bookings/create_service_spec.rb b/app_delta/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..2831047
--- /dev/null
+++ b/app_delta/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,80 @@
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
+      it "creates 5 orders spaced one week apart" do
+        expect { result }.to change(Order, :count).by(5)
+
+        orders = result[:recurring_booking].orders.order(:scheduled_at)
+        first_time = orders.first.scheduled_at
+
+        orders.each_with_index do |order, i|
+          expect(order.scheduled_at).to be_within(1.second).of(first_time + i.weeks)
+          expect(order.duration_minutes).to eq(120)
+          expect(order.amount_cents).to eq(350_000)
+          expect(order.client).to eq(client)
+          expect(order.provider).to eq(provider)
+        end
+      end
+
+      it "creates a payment for each order" do
+        expect { result }.to change(Payment, :count).by(5)
+
+        result[:recurring_booking].orders.each do |order|
+          payment = order.payment
+          expect(payment).to be_present
+          expect(payment.amount_cents).to eq(350_000)
+          expect(payment.fee_cents).to eq(35_000)
+          expect(payment.status).to eq("pending")
+        end
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=recurring_booking_created")
+      end
+
+      it "defaults currency to RUB" do
+        params_without_currency = valid_params.except(:currency)
+        result = described_class.new(client: client, provider: provider, params: params_without_currency).call
+        expect(result[:recurring_booking].currency).to eq("RUB")
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
+        expect { result }.not_to change(Payment, :count)
+      end
+    end
+  end
+end
```
