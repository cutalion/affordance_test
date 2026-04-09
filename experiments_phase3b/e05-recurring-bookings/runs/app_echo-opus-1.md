# Experiment: e05-recurring-bookings
# App: app_echo | Model: opus | Run: 1
# Branch: debt_experiment/e05-recurring-bookings/app_echo/opus/run-1

---

## Claude Output

All 153 specs pass. Here's what was implemented:

## Summary

**Recurring weekly bookings** — 5 sessions with the same provider, scheduled 1 week apart.

### Changes:

1. **`app/models/request.rb`** — Added `recurring?` method, `recurring_siblings` method, and scopes `recurring` and `by_recurring_group`

2. **`app/services/requests/create_recurring_service.rb`** (new) — Creates 5 requests atomically in a transaction, each sharing a UUID `recurring_group_id` with `recurring_index` 0-4. Sends a single `recurring_booking_created` notification.

3. **`app/controllers/api/requests_controller.rb`** — The `create` action now accepts `recurring: true` param. When set, it delegates to `CreateRecurringService` and returns a response with `recurring_group_id` and all 5 requests. JSON responses now include `recurring_group_id` and `recurring_index` fields.

4. **Specs** — Added model specs for recurring scopes/methods and a full service spec for `CreateRecurringService` (valid params, invalid params, scheduling, notifications).

### Usage:

```bash
# Create a recurring booking (5 weekly sessions)
POST /api/requests?recurring=true
{
  "provider_id": 1,
  "scheduled_at": "2026-04-15T10:00:00Z",
  "duration_minutes": 120,
  "amount_cents": 350000,
  "location": "123 Main St"
}
```

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..33849c7 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -21,16 +21,10 @@ def create
       provider = Provider.find_by(id: params[:provider_id])
       return render_not_found unless provider
 
-      result = Requests::CreateService.new(
-        client: client,
-        provider: provider,
-        params: request_params
-      ).call
-
-      if result[:success]
-        render json: request_detail_json(result[:request]), status: :created
+      if params[:recurring].present?
+        create_recurring(client, provider)
       else
-        render_unprocessable(result[:errors].full_messages)
+        create_single(client, provider)
       end
     end
 
@@ -119,6 +113,37 @@ def scoped_requests
       end
     end
 
+    def create_single(client, provider)
+      result = Requests::CreateService.new(
+        client: client,
+        provider: provider,
+        params: request_params
+      ).call
+
+      if result[:success]
+        render json: request_detail_json(result[:request]), status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
+    def create_recurring(client, provider)
+      result = Requests::CreateRecurringService.new(
+        client: client,
+        provider: provider,
+        params: request_params
+      ).call
+
+      if result[:success]
+        render json: {
+          recurring_group_id: result[:recurring_group_id],
+          requests: result[:requests].map { |r| request_detail_json(r) }
+        }, status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def request_params
       params.permit(:scheduled_at, :duration_minutes, :location, :notes, :amount_cents, :currency)
     end
@@ -139,7 +164,9 @@ def request_summary_json(request)
         amount_cents: request.amount_cents,
         currency: request.currency,
         client_id: request.client_id,
-        provider_id: request.provider_id
+        provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id,
+        recurring_index: request.recurring_index
       }
     end
 
@@ -162,6 +189,8 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id,
+        recurring_index: request.recurring_index,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..2c868d3 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -28,6 +28,17 @@ class Request < ApplicationRecord
     scope
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
+  scope :recurring, -> { where.not(recurring_group_id: nil) }
+  scope :by_recurring_group, ->(group_id) { where(recurring_group_id: group_id) }
+
+  def recurring?
+    recurring_group_id.present?
+  end
+
+  def recurring_siblings
+    return Request.none unless recurring?
+    Request.where(recurring_group_id: recurring_group_id).where.not(id: id)
+  end
 
   aasm column: :state do
     state :pending, initial: true
diff --git a/app_echo/app/services/requests/create_recurring_service.rb b/app_echo/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..a69aa89
--- /dev/null
+++ b/app_echo/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,46 @@
+module Requests
+  class CreateRecurringService
+    SESSIONS_COUNT = 5
+    INTERVAL = 1.week
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      recurring_group_id = SecureRandom.uuid
+      base_scheduled_at = @params[:scheduled_at].present? ? Time.zone.parse(@params[:scheduled_at].to_s) : nil
+
+      requests = ActiveRecord::Base.transaction do
+        SESSIONS_COUNT.times.map do |index|
+          Request.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: base_scheduled_at && (base_scheduled_at + (index * INTERVAL)),
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB",
+            recurring_group_id: recurring_group_id,
+            recurring_index: index
+          )
+        end
+      end
+
+      NotificationService.notify(
+        @provider,
+        :recurring_booking_created,
+        recurring_group_id: recurring_group_id,
+        request_ids: requests.map(&:id).join(","),
+        sessions_count: SESSIONS_COUNT
+      )
+
+      { success: true, requests: requests, recurring_group_id: recurring_group_id }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
diff --git a/app_echo/spec/models/request_spec.rb b/app_echo/spec/models/request_spec.rb
index a9aece5..d92ee6b 100644
--- a/app_echo/spec/models/request_spec.rb
+++ b/app_echo/spec/models/request_spec.rb
@@ -182,6 +182,32 @@
     end
   end
 
+  describe "#recurring?" do
+    it "returns true when recurring_group_id is present" do
+      request = build(:request, recurring_group_id: "group-1", recurring_index: 0)
+      expect(request).to be_recurring
+    end
+
+    it "returns false when recurring_group_id is nil" do
+      request = build(:request)
+      expect(request).not_to be_recurring
+    end
+  end
+
+  describe "#recurring_siblings" do
+    it "returns other requests in the same recurring group" do
+      r1 = create(:request, recurring_group_id: "group-1", recurring_index: 0)
+      r2 = create(:request, recurring_group_id: "group-1", recurring_index: 1)
+      r3 = create(:request, recurring_group_id: "group-1", recurring_index: 2)
+      expect(r1.recurring_siblings).to contain_exactly(r2, r3)
+    end
+
+    it "returns none for non-recurring requests" do
+      request = create(:request)
+      expect(request.recurring_siblings).to be_empty
+    end
+  end
+
   describe "scopes" do
     let!(:future_request) { create(:request, scheduled_at: 1.day.from_now) }
     let!(:past_request) { create(:request, scheduled_at: 1.day.ago) }
@@ -212,6 +238,24 @@
       end
     end
 
+    describe ".recurring" do
+      it "returns only requests with a recurring_group_id" do
+        recurring = create(:request, recurring_group_id: "group-1", recurring_index: 0)
+        non_recurring = create(:request)
+        expect(Request.recurring).to include(recurring)
+        expect(Request.recurring).not_to include(non_recurring)
+      end
+    end
+
+    describe ".by_recurring_group" do
+      it "returns requests matching the group id" do
+        r1 = create(:request, recurring_group_id: "group-1", recurring_index: 0)
+        r2 = create(:request, recurring_group_id: "group-1", recurring_index: 1)
+        r3 = create(:request, recurring_group_id: "group-2", recurring_index: 0)
+        expect(Request.by_recurring_group("group-1")).to contain_exactly(r1, r2)
+      end
+    end
+
     describe ".sorted" do
       it "returns requests sorted by scheduled_at descending" do
         sorted = Request.sorted.to_a
diff --git a/app_echo/spec/services/requests/create_recurring_service_spec.rb b/app_echo/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..a058b77
--- /dev/null
+++ b/app_echo/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,87 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:base_time) { 3.days.from_now.beginning_of_hour }
+  let(:valid_params) do
+    {
+      scheduled_at: base_time.iso8601,
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
+      it "creates 5 requests" do
+        expect { result }.to change(Request, :count).by(5)
+      end
+
+      it "returns success with all requests" do
+        expect(result[:success]).to be true
+        expect(result[:requests].size).to eq(5)
+        expect(result[:recurring_group_id]).to be_present
+      end
+
+      it "schedules requests one week apart" do
+        requests = result[:requests]
+        requests.each_with_index do |request, index|
+          expected_time = base_time + (index * 1.week)
+          expect(request.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "assigns sequential recurring_index values" do
+        requests = result[:requests]
+        expect(requests.map(&:recurring_index)).to eq([0, 1, 2, 3, 4])
+      end
+
+      it "shares the same recurring_group_id" do
+        requests = result[:requests]
+        group_ids = requests.map(&:recurring_group_id).uniq
+        expect(group_ids.size).to eq(1)
+        expect(group_ids.first).to be_present
+      end
+
+      it "sets the same amount, duration, and location on all requests" do
+        requests = result[:requests]
+        requests.each do |request|
+          expect(request.amount_cents).to eq(350_000)
+          expect(request.duration_minutes).to eq(120)
+          expect(request.location).to eq("123 Main St")
+        end
+      end
+
+      it "creates all requests in pending state" do
+        requests = result[:requests]
+        expect(requests.map(&:state).uniq).to eq(["pending"])
+      end
+
+      it "sends a single recurring notification (across all channels)" do
+        result
+        log = read_notification_log
+        expect(log).to include("event=recurring_booking_created")
+        expect(log.scan("recurring_booking_created").size).to eq(3) # push, sms, email
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
+      it "does not create any requests" do
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+  end
+end
```
