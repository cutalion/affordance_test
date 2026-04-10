# Experiment: e05-recurring-bookings
# App: app_echo | Model: opus | Run: 1
# Branch: debt_experiment/e05-recurring-bookings/app_echo/opus/run-1

---

## Claude Output

All 156 tests pass (0 failures). Here's a summary of what was implemented:

### Recurring Weekly Bookings

**Migration:** Added `recurring_group_id` (string, indexed) to the `requests` table to link related bookings.

**Model (`Request`):**
- `recurring?` — returns true if the request belongs to a recurring group
- `recurring_siblings` — returns other requests in the same recurring group
- `by_recurring_group` scope — filter requests by group ID

**Service (`Requests::CreateRecurringService`):**
- Creates 5 requests in a single transaction, each scheduled 1 week apart
- All share the same UUID `recurring_group_id`
- Same provider, duration, location, notes, and amount for all sessions
- Notifies the provider once with a `recurring_booking_created` event
- Rolls back all requests if any validation fails

**API Endpoint:** `POST /api/requests/recurring`
- Accepts the same params as regular request creation (`provider_id`, `scheduled_at`, `duration_minutes`, `location`, `notes`, `amount_cents`, `currency`)
- Returns the `recurring_group_id` and all 5 request objects
- `scheduled_at` is the start of the first session; subsequent sessions are +1/+2/+3/+4 weeks

**Tests:** 17 new specs covering the service (valid creation, scheduling, grouping, notifications, error handling, transaction rollback) and model methods (recurring detection, sibling queries, scope filtering).

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..0b5f314 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
@@ -34,6 +34,29 @@ def create
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
+        render json: {
+          recurring_group_id: result[:recurring_group_id],
+          requests: result[:requests].map { |r| request_detail_json(r) }
+        }, status: :created
+      else
+        render_unprocessable(result[:errors])
+      end
+    end
+
     def accept
       actor = current_user
       result = Requests::AcceptService.new(request: @request, actor: actor).call
@@ -160,6 +183,7 @@ def request_detail_json(request)
         expired_at: request.expired_at,
         started_at: request.started_at,
         completed_at: request.completed_at,
+        recurring_group_id: request.recurring_group_id,
         client_id: request.client_id,
         provider_id: request.provider_id,
         payment: request.payment ? {
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..7db4690 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -8,6 +8,17 @@ class Request < ApplicationRecord
   has_one :payment, dependent: :destroy
   has_many :reviews, dependent: :destroy
 
+  scope :by_recurring_group, ->(group_id) { where(recurring_group_id: group_id) if group_id.present? }
+
+  def recurring?
+    recurring_group_id.present?
+  end
+
+  def recurring_siblings
+    return Request.none unless recurring?
+    Request.where(recurring_group_id: recurring_group_id).where.not(id: id)
+  end
+
   validates :scheduled_at, presence: true
   validates :duration_minutes, presence: true, numericality: { greater_than: 0 }
   validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
diff --git a/app_echo/app/services/requests/create_recurring_service.rb b/app_echo/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..0f41f02
--- /dev/null
+++ b/app_echo/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,50 @@
+module Requests
+  class CreateRecurringService
+    SESSIONS_COUNT = 5
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      scheduled_at = @params[:scheduled_at]
+      return { success: false, errors: ["scheduled_at is required"] } if scheduled_at.blank?
+
+      scheduled_at = Time.zone.parse(scheduled_at.to_s) unless scheduled_at.is_a?(Time) || scheduled_at.is_a?(ActiveSupport::TimeWithZone)
+      recurring_group_id = SecureRandom.uuid
+
+      requests = []
+
+      ActiveRecord::Base.transaction do
+        SESSIONS_COUNT.times do |i|
+          request = Request.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: scheduled_at + i.weeks,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB",
+            recurring_group_id: recurring_group_id
+          )
+          requests << request
+        end
+      end
+
+      NotificationService.notify(
+        @provider,
+        :recurring_booking_created,
+        recurring_group_id: recurring_group_id,
+        sessions_count: SESSIONS_COUNT,
+        request_ids: requests.map(&:id).join(",")
+      )
+
+      { success: true, requests: requests, recurring_group_id: recurring_group_id }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors.full_messages }
+    end
+  end
+end
diff --git a/app_echo/config/routes.rb b/app_echo/config/routes.rb
index da43a53..99f00d5 100644
--- a/app_echo/config/routes.rb
+++ b/app_echo/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :recurring
+      end
       member do
         patch :accept
         patch :decline
diff --git a/app_echo/db/migrate/20260410084848_add_recurring_group_id_to_requests.rb b/app_echo/db/migrate/20260410084848_add_recurring_group_id_to_requests.rb
new file mode 100644
index 0000000..af3548d
--- /dev/null
+++ b/app_echo/db/migrate/20260410084848_add_recurring_group_id_to_requests.rb
@@ -0,0 +1,6 @@
+class AddRecurringGroupIdToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :recurring_group_id, :string
+    add_index :requests, :recurring_group_id
+  end
+end
diff --git a/app_echo/db/schema.rb b/app_echo/db/schema.rb
index 12d0e60..c3b4679 100644
--- a/app_echo/db/schema.rb
+++ b/app_echo/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140808) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_084848) do
   create_table "announcements", force: :cascade do |t|
     t.integer "budget_cents"
     t.integer "client_id", null: false
@@ -102,6 +102,7 @@
     t.text "notes"
     t.integer "proposed_amount_cents"
     t.integer "provider_id", null: false
+    t.string "recurring_group_id"
     t.text "reject_reason"
     t.text "response_message"
     t.datetime "scheduled_at", null: false
@@ -111,6 +112,7 @@
     t.index ["announcement_id"], name: "index_requests_on_announcement_id"
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_group_id"], name: "index_requests_on_recurring_group_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
   end
diff --git a/app_echo/spec/models/request_spec.rb b/app_echo/spec/models/request_spec.rb
index a9aece5..4186b2d 100644
--- a/app_echo/spec/models/request_spec.rb
+++ b/app_echo/spec/models/request_spec.rb
@@ -218,5 +218,54 @@
         expect(sorted.first.scheduled_at).to be >= sorted.last.scheduled_at
       end
     end
+
+    describe ".by_recurring_group" do
+      let(:group_id) { SecureRandom.uuid }
+      let!(:recurring_request) { create(:request, recurring_group_id: group_id) }
+      let!(:other_request) { create(:request) }
+
+      it "filters by recurring_group_id" do
+        expect(Request.by_recurring_group(group_id)).to include(recurring_request)
+        expect(Request.by_recurring_group(group_id)).not_to include(other_request)
+      end
+
+      it "returns all when group_id is blank" do
+        expect(Request.by_recurring_group(nil).count).to eq(Request.count)
+      end
+    end
+  end
+
+  describe "#recurring?" do
+    it "returns true when recurring_group_id is present" do
+      request = build(:request, recurring_group_id: SecureRandom.uuid)
+      expect(request).to be_recurring
+    end
+
+    it "returns false when recurring_group_id is nil" do
+      request = build(:request, recurring_group_id: nil)
+      expect(request).not_to be_recurring
+    end
+  end
+
+  describe "#recurring_siblings" do
+    let(:group_id) { SecureRandom.uuid }
+    let!(:request1) { create(:request, recurring_group_id: group_id) }
+    let!(:request2) { create(:request, recurring_group_id: group_id) }
+    let!(:request3) { create(:request, recurring_group_id: group_id) }
+    let!(:unrelated) { create(:request) }
+
+    it "returns other requests in the same group" do
+      siblings = request1.recurring_siblings
+      expect(siblings).to include(request2, request3)
+      expect(siblings).not_to include(request1)
+    end
+
+    it "does not include unrelated requests" do
+      expect(request1.recurring_siblings).not_to include(unrelated)
+    end
+
+    it "returns none for non-recurring requests" do
+      expect(unrelated.recurring_siblings).to be_empty
+    end
   end
 end
diff --git a/app_echo/spec/services/requests/create_recurring_service_spec.rb b/app_echo/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..86de78e
--- /dev/null
+++ b/app_echo/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,115 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:start_time) { 3.days.from_now }
+  let(:valid_params) do
+    {
+      scheduled_at: start_time,
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
+        expect(result[:success]).to be true
+        expect(result[:requests].size).to eq(5)
+      end
+
+      it "schedules each request 1 week apart" do
+        requests = result[:requests]
+        requests.each_with_index do |request, i|
+          expected_time = start_time + i.weeks
+          expect(request.scheduled_at).to be_within(1.second).of(expected_time)
+        end
+      end
+
+      it "assigns the same recurring_group_id to all requests" do
+        requests = result[:requests]
+        group_id = result[:recurring_group_id]
+        expect(group_id).to be_present
+        requests.each do |request|
+          expect(request.recurring_group_id).to eq(group_id)
+        end
+      end
+
+      it "sets all requests to pending state" do
+        result[:requests].each do |request|
+          expect(request.state).to eq("pending")
+        end
+      end
+
+      it "copies shared attributes to all requests" do
+        result[:requests].each do |request|
+          expect(request.duration_minutes).to eq(120)
+          expect(request.location).to eq("123 Main St")
+          expect(request.amount_cents).to eq(350_000)
+          expect(request.currency).to eq("RUB")
+          expect(request.client).to eq(client)
+          expect(request.provider).to eq(provider)
+        end
+      end
+
+      it "notifies the provider" do
+        result
+        expect(read_notification_log).to include("event=recurring_booking_created")
+      end
+
+      it "returns the recurring_group_id" do
+        expect(result[:recurring_group_id]).to match(/\A[0-9a-f-]{36}\z/)
+      end
+    end
+
+    context "with missing scheduled_at" do
+      let(:valid_params) { { scheduled_at: nil, duration_minutes: 120, amount_cents: 350_000 } }
+
+      it "returns an error" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to include("scheduled_at is required")
+      end
+
+      it "does not create any requests" do
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: start_time, duration_minutes: 0, amount_cents: 350_000 } }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "does not create any requests (transaction rollback)" do
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+
+    context "with string scheduled_at" do
+      let(:valid_params) do
+        {
+          scheduled_at: start_time.iso8601,
+          duration_minutes: 120,
+          location: "123 Main St",
+          amount_cents: 350_000,
+          currency: "RUB"
+        }
+      end
+
+      it "parses and creates 5 requests" do
+        expect(result[:success]).to be true
+        expect(result[:requests].size).to eq(5)
+      end
+    end
+  end
+end
```
