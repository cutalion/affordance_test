# Experiment: e05-recurring-bookings
# App: app_charlie | Model: opus | Run: 2
# Branch: debt_experiment/e05-recurring-bookings/app_charlie/opus/run-2

---

## Claude Output

All 125 tests pass (including the new ones). Here's what was implemented:

**Recurring Weekly Bookings (5 sessions)**

**Model** (`app/models/request.rb`):
- `recurring?` — checks if request belongs to a recurring group
- `recurring_siblings` — returns other requests in the same group
- `.recurring` scope — filters to recurring requests only
- `.by_recurring_group(id)` scope — filters by group ID

**Service** (`app/services/requests/create_recurring_service.rb`):
- Creates 5 requests in a transaction, each scheduled 1 week apart
- Links them via a shared `recurring_group_id` (UUID) with `recurring_index` 1-5
- Same provider, duration, location, notes, and amount for all 5
- Notifies the provider once with all request IDs
- Rolls back all requests if any validation fails

**API Endpoint**: `POST /api/requests/recurring`
- Same params as single request creation (`provider_id`, `scheduled_at`, `duration_minutes`, etc.)
- Returns `recurring_group_id` + array of all 5 request details
- Each request is independently managed (accept/decline/cancel individually)

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..bc93bd2 100644
--- a/app_charlie/app/controllers/api/requests_controller.rb
+++ b/app_charlie/app/controllers/api/requests_controller.rb
@@ -34,6 +34,29 @@ def create
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
       provider = current_provider!
       return if performed?
@@ -141,7 +164,9 @@ def request_summary_json(request)
         amount_cents: request.amount_cents,
         currency: request.currency,
         client_id: request.client_id,
-        provider_id: request.provider_id
+        provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id,
+        recurring_index: request.recurring_index
       }
     end
 
@@ -164,6 +189,8 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id,
+        recurring_index: request.recurring_index,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..2ff144a 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -27,6 +27,17 @@ class Request < ApplicationRecord
     scope
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
+  scope :recurring, -> { where.not(recurring_group_id: nil) }
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
 
   aasm column: :state do
     state :pending, initial: true
diff --git a/app_charlie/app/services/requests/create_recurring_service.rb b/app_charlie/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..3af59ad
--- /dev/null
+++ b/app_charlie/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,57 @@
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
+      scheduled_at = parse_scheduled_at
+      return { success: false, errors: ["scheduled_at is required"] } unless scheduled_at
+
+      group_id = SecureRandom.uuid
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
+            recurring_group_id: group_id,
+            recurring_index: i + 1
+          )
+          requests << request
+        end
+      end
+
+      NotificationService.notify(
+        @provider,
+        :recurring_request_created,
+        request_ids: requests.map(&:id),
+        recurring_group_id: group_id,
+        sessions_count: SESSIONS_COUNT
+      )
+
+      { success: true, requests: requests, recurring_group_id: group_id }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors.full_messages }
+    end
+
+    private
+
+    def parse_scheduled_at
+      value = @params[:scheduled_at]
+      return nil if value.blank?
+      value.is_a?(String) ? Time.zone.parse(value) : value
+    end
+  end
+end
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..0da5115 100644
--- a/app_charlie/config/routes.rb
+++ b/app_charlie/config/routes.rb
@@ -11,6 +11,9 @@
     end
 
     resources :requests, only: [:index, :show, :create] do
+      collection do
+        post :recurring, action: :create_recurring
+      end
       member do
         patch :accept
         patch :decline
diff --git a/app_charlie/spec/models/request_spec.rb b/app_charlie/spec/models/request_spec.rb
index a9aece5..e8d352c 100644
--- a/app_charlie/spec/models/request_spec.rb
+++ b/app_charlie/spec/models/request_spec.rb
@@ -218,5 +218,59 @@
         expect(sorted.first.scheduled_at).to be >= sorted.last.scheduled_at
       end
     end
+
+    describe ".recurring" do
+      let!(:recurring_request) { create(:request, recurring_group_id: "abc-123", recurring_index: 1) }
+      let!(:regular_request) { create(:request) }
+
+      it "returns only requests with a recurring_group_id" do
+        expect(Request.recurring).to include(recurring_request)
+        expect(Request.recurring).not_to include(regular_request)
+      end
+    end
+
+    describe ".by_recurring_group" do
+      let!(:group_a) { create(:request, recurring_group_id: "group-a", recurring_index: 1) }
+      let!(:group_b) { create(:request, recurring_group_id: "group-b", recurring_index: 1) }
+
+      it "filters by recurring_group_id" do
+        expect(Request.by_recurring_group("group-a")).to include(group_a)
+        expect(Request.by_recurring_group("group-a")).not_to include(group_b)
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
+      request = build(:request, recurring_group_id: "abc-123", recurring_index: 1)
+      expect(request.recurring?).to be true
+    end
+
+    it "returns false when recurring_group_id is nil" do
+      request = build(:request)
+      expect(request.recurring?).to be false
+    end
+  end
+
+  describe "#recurring_siblings" do
+    let(:group_id) { "test-group" }
+    let!(:request1) { create(:request, recurring_group_id: group_id, recurring_index: 1) }
+    let!(:request2) { create(:request, recurring_group_id: group_id, recurring_index: 2) }
+    let!(:request3) { create(:request, recurring_group_id: group_id, recurring_index: 3) }
+    let!(:other_request) { create(:request) }
+
+    it "returns other requests in the same recurring group" do
+      siblings = request1.recurring_siblings
+      expect(siblings).to include(request2, request3)
+      expect(siblings).not_to include(request1, other_request)
+    end
+
+    it "returns empty relation for non-recurring requests" do
+      expect(other_request.recurring_siblings).to be_empty
+    end
   end
 end
diff --git a/app_charlie/spec/services/requests/create_recurring_service_spec.rb b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..da3b650
--- /dev/null
+++ b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,99 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now }
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
+        requests.each_cons(2) do |a, b|
+          expect(b.scheduled_at).to be_within(1.second).of(a.scheduled_at + 1.week)
+        end
+      end
+
+      it "assigns sequential recurring_index values 1 through 5" do
+        requests = result[:requests]
+        expect(requests.map(&:recurring_index)).to eq([1, 2, 3, 4, 5])
+      end
+
+      it "assigns the same recurring_group_id to all requests" do
+        requests = result[:requests]
+        group_ids = requests.map(&:recurring_group_id).uniq
+        expect(group_ids.size).to eq(1)
+        expect(group_ids.first).to be_present
+      end
+
+      it "creates all requests in pending state" do
+        requests = result[:requests]
+        expect(requests.map(&:state).uniq).to eq(["pending"])
+      end
+
+      it "copies amount, duration, location, and notes to all requests" do
+        requests = result[:requests]
+        requests.each do |r|
+          expect(r.amount_cents).to eq(350_000)
+          expect(r.duration_minutes).to eq(120)
+          expect(r.location).to eq("123 Main St")
+          expect(r.notes).to eq("Weekly session")
+        end
+      end
+
+      it "notifies the provider" do
+        result
+        log = read_notification_log
+        expect(log).to include("event=recurring_request_created")
+      end
+    end
+
+    context "with missing scheduled_at" do
+      let(:valid_params) { { duration_minutes: 120, amount_cents: 350_000 } }
+
+      it "returns failure" do
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
+      let(:valid_params) { { scheduled_at: scheduled_at, duration_minutes: 0, amount_cents: -1 } }
+
+      it "returns errors" do
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
+      end
+
+      it "rolls back all requests on failure" do
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+  end
+end
```
