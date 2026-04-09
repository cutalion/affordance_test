# Experiment: e05-recurring-bookings
# App: app_bravo | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_bravo/opus/run-3

---

## Claude Output

All 135 specs pass (including 11 new ones). Here's what was implemented:

**Model** — `RecurringBooking` with associations to `client`, `provider`, and `has_many :requests`. Validates `sessions_count` must be exactly 5.

**Request model** — Added `belongs_to :recurring_booking, optional: true` association.

**Service** — `RecurringBookings::CreateService` creates a recurring booking and 5 requests in a transaction, each scheduled 1 week apart (same day/time). Notifies the provider.

**Controller** — `Api::RecurringBookingsController` with `index`, `show`, and `create` actions. The `show` response includes the list of individual requests.

**Route** — `POST /api/recurring_bookings`, `GET /api/recurring_bookings`, `GET /api/recurring_bookings/:id`

**Specs** — Model validations and service specs covering: creation of 5 weekly requests, correct scheduling, linking to recurring booking, provider notification, and transactional rollback on invalid params.

---

## Git Diff

```diff
diff --git a/app_bravo/app/controllers/api/recurring_bookings_controller.rb b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
new file mode 100644
index 0000000..cc14a0c
--- /dev/null
+++ b/app_bravo/app/controllers/api/recurring_bookings_controller.rb
@@ -0,0 +1,70 @@
+module Api
+  class RecurringBookingsController < BaseController
+    def index
+      client = current_client!
+      return if performed?
+
+      bookings = RecurringBooking.where(client: client)
+        .includes(:requests)
+        .order(created_at: :desc)
+        .page(params[:page])
+
+      render json: bookings.map { |b| recurring_booking_json(b) }
+    end
+
+    def show
+      booking = RecurringBooking.find_by(id: params[:id])
+      return render_not_found unless booking
+
+      render json: recurring_booking_json(booking, include_requests: true)
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
+        render json: recurring_booking_json(result[:recurring_booking], include_requests: true), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
+    private
+
+    def recurring_booking_params
+      params.permit(:scheduled_at, :duration_minutes, :location, :notes)
+    end
+
+    def recurring_booking_json(booking, include_requests: false)
+      json = {
+        id: booking.id,
+        client_id: booking.client_id,
+        provider_id: booking.provider_id,
+        scheduled_at: booking.scheduled_at,
+        duration_minutes: booking.duration_minutes,
+        sessions_count: booking.sessions_count,
+        location: booking.location,
+        notes: booking.notes,
+        created_at: booking.created_at
+      }
+
+      if include_requests
+        json[:requests] = booking.requests.order(:scheduled_at).map do |r|
+          { id: r.id, state: r.state, scheduled_at: r.scheduled_at }
+        end
+      end
+
+      json
+    end
+  end
+end
diff --git a/app_bravo/app/models/recurring_booking.rb b/app_bravo/app/models/recurring_booking.rb
new file mode 100644
index 0000000..9bea015
--- /dev/null
+++ b/app_bravo/app/models/recurring_booking.rb
@@ -0,0 +1,9 @@
+class RecurringBooking < ApplicationRecord
+  belongs_to :client
+  belongs_to :provider
+  has_many :requests, dependent: :nullify
+
+  validates :scheduled_at, presence: true
+  validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
+  validates :sessions_count, presence: true, numericality: { equal_to: 5 }
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
index 0000000..4436291
--- /dev/null
+++ b/app_bravo/app/services/recurring_bookings/create_service.rb
@@ -0,0 +1,48 @@
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
+          scheduled_at: @params[:scheduled_at],
+          duration_minutes: @params[:duration_minutes],
+          location: @params[:location],
+          notes: @params[:notes],
+          sessions_count: SESSIONS_COUNT
+        )
+
+        requests = SESSIONS_COUNT.times.map do |i|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            recurring_booking: recurring_booking,
+            scheduled_at: Time.parse(@params[:scheduled_at].to_s) + i.weeks,
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
diff --git a/app_bravo/config/routes.rb b/app_bravo/config/routes.rb
index 8d32af9..17c3cf2 100644
--- a/app_bravo/config/routes.rb
+++ b/app_bravo/config/routes.rb
@@ -10,6 +10,8 @@
       patch :default, on: :member, action: :set_default
     end
 
+    resources :recurring_bookings, only: [:index, :show, :create]
+
     resources :requests, only: [:index, :show, :create] do
       member do
         patch :accept
diff --git a/app_bravo/spec/factories/recurring_bookings.rb b/app_bravo/spec/factories/recurring_bookings.rb
new file mode 100644
index 0000000..35d9beb
--- /dev/null
+++ b/app_bravo/spec/factories/recurring_bookings.rb
@@ -0,0 +1,11 @@
+FactoryBot.define do
+  factory :recurring_booking do
+    client
+    provider
+    scheduled_at { 3.days.from_now }
+    duration_minutes { 120 }
+    sessions_count { 5 }
+    location { "123 Main St" }
+    notes { "Weekly session" }
+  end
+end
diff --git a/app_bravo/spec/models/recurring_booking_spec.rb b/app_bravo/spec/models/recurring_booking_spec.rb
new file mode 100644
index 0000000..b3fe894
--- /dev/null
+++ b/app_bravo/spec/models/recurring_booking_spec.rb
@@ -0,0 +1,24 @@
+require "rails_helper"
+
+RSpec.describe RecurringBooking do
+  subject(:booking) { build(:recurring_booking) }
+
+  it "is valid with default factory attributes" do
+    expect(booking).to be_valid
+  end
+
+  it "requires scheduled_at" do
+    booking.scheduled_at = nil
+    expect(booking).not_to be_valid
+  end
+
+  it "requires duration_minutes > 0" do
+    booking.duration_minutes = 0
+    expect(booking).not_to be_valid
+  end
+
+  it "requires sessions_count to be 5" do
+    booking.sessions_count = 3
+    expect(booking).not_to be_valid
+  end
+end
diff --git a/app_bravo/spec/services/recurring_bookings/create_service_spec.rb b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
new file mode 100644
index 0000000..2f00ef3
--- /dev/null
+++ b/app_bravo/spec/services/recurring_bookings/create_service_spec.rb
@@ -0,0 +1,65 @@
+require "rails_helper"
+
+RSpec.describe RecurringBookings::CreateService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now }
+  let(:params) do
+    {
+      scheduled_at: scheduled_at,
+      duration_minutes: 120,
+      location: "123 Main St",
+      notes: "Weekly session"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: params).call }
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
+        expect(result[:requests].size).to eq(5)
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
+        booking = result[:recurring_booking]
+        result[:requests].each do |request|
+          expect(request.recurring_booking).to eq(booking)
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
+      let(:params) { { scheduled_at: nil, duration_minutes: nil } }
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
