# Experiment: e05-recurring-bookings
# App: app_echo | Model: opus | Run: 2
# Branch: debt_experiment/e05-recurring-bookings/app_echo/opus/run-2

---

## Claude Output

All done. Here's what was implemented:

**Recurring Weekly Bookings — 5 sessions with the same provider**

**Model** (`app/models/request.rb`):
- Added `by_recurring_group` scope to query all requests in a recurring group
- Added `recurring?` helper method

**Service** (`app/services/requests/create_recurring_service.rb`):
- Creates 5 requests in a single transaction, each scheduled 1 week apart
- Links them with a shared `recurring_group_id` (UUID) and sequential `recurring_index` (0-4)
- Notifies the provider for each created request
- Rolls back all requests if any validation fails

**API Endpoint** (`POST /api/requests/recurring`):
- Same params as single request creation (`provider_id`, `scheduled_at`, `duration_minutes`, `location`, `notes`, `amount_cents`, `currency`)
- Returns the `recurring_group_id` and all 5 request details
- `scheduled_at` is the time for the first session; subsequent sessions are +1 week each

**JSON responses** now include `recurring_group_id` and `recurring_index` fields.

**Admin views** show a recurring indicator in the index and a "Recurring Sessions" table on the show page linking to all sibling requests.

**Tests**: 150 specs, 0 failures.

---

## Git Diff

```diff
diff --git a/app_echo/app/controllers/admin/requests_controller.rb b/app_echo/app/controllers/admin/requests_controller.rb
index 7cecaef..9b9e730 100644
--- a/app_echo/app/controllers/admin/requests_controller.rb
+++ b/app_echo/app/controllers/admin/requests_controller.rb
@@ -13,6 +13,10 @@ def index
 
     def show
       @request = Request.includes(:client, :provider).find(params[:id])
+      if @request.recurring?
+        @recurring_requests = Request.where(recurring_group_id: @request.recurring_group_id)
+                                     .order(:recurring_index)
+      end
     end
   end
 end
diff --git a/app_echo/app/controllers/api/requests_controller.rb b/app_echo/app/controllers/api/requests_controller.rb
index 420a57a..48215e3 100644
--- a/app_echo/app/controllers/api/requests_controller.rb
+++ b/app_echo/app/controllers/api/requests_controller.rb
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
       actor = current_user
       result = Requests::AcceptService.new(request: @request, actor: actor).call
@@ -139,7 +162,8 @@ def request_summary_json(request)
         amount_cents: request.amount_cents,
         currency: request.currency,
         client_id: request.client_id,
-        provider_id: request.provider_id
+        provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id
       }
     end
 
@@ -162,6 +186,8 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id,
+        recurring_index: request.recurring_index,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
diff --git a/app_echo/app/models/request.rb b/app_echo/app/models/request.rb
index 7795b75..ffe20dc 100644
--- a/app_echo/app/models/request.rb
+++ b/app_echo/app/models/request.rb
@@ -28,6 +28,11 @@ class Request < ApplicationRecord
     scope
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
+  scope :by_recurring_group, ->(group_id) { where(recurring_group_id: group_id) if group_id.present? }
+
+  def recurring?
+    recurring_group_id.present?
+  end
 
   aasm column: :state do
     state :pending, initial: true
diff --git a/app_echo/app/services/requests/create_recurring_service.rb b/app_echo/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..dbf2efa
--- /dev/null
+++ b/app_echo/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,45 @@
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
+      base_time = Time.zone.parse(@params[:scheduled_at].to_s)
+      return { success: false, errors: ["scheduled_at is required"] } unless base_time
+
+      group_id = SecureRandom.uuid
+      requests = []
+
+      ActiveRecord::Base.transaction do
+        SESSIONS_COUNT.times do |i|
+          request = Request.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: base_time + i.weeks,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB",
+            recurring_group_id: group_id,
+            recurring_index: i
+          )
+          requests << request
+        end
+      end
+
+      requests.each do |request|
+        NotificationService.notify(@provider, :request_created, request_id: request.id)
+      end
+
+      { success: true, requests: requests, recurring_group_id: group_id }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors.full_messages }
+    end
+  end
+end
diff --git a/app_echo/app/views/admin/requests/index.html.erb b/app_echo/app/views/admin/requests/index.html.erb
index 307ea55..bf1f5b9 100644
--- a/app_echo/app/views/admin/requests/index.html.erb
+++ b/app_echo/app/views/admin/requests/index.html.erb
@@ -38,7 +38,7 @@
         <td><%= link_to "##{request.id}", admin_request_path(request) %></td>
         <td><%= link_to request.client.name, admin_client_path(request.client) %></td>
         <td><%= link_to request.provider.name, admin_provider_path(request.provider) %></td>
-        <td><span class="badge badge-<%= request.state %>"><%= request.state.humanize %></span></td>
+        <td><span class="badge badge-<%= request.state %>"><%= request.state.humanize %></span><%= " ♻" if request.recurring? %></td>
         <td><%= request.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
         <td><%= number_with_precision(request.amount_cents.to_f / 100, precision: 2) %> <%= request.currency %></td>
         <td><%= request.created_at&.strftime("%Y-%m-%d") %></td>
diff --git a/app_echo/app/views/admin/requests/show.html.erb b/app_echo/app/views/admin/requests/show.html.erb
index cd6241e..cfbb0e0 100644
--- a/app_echo/app/views/admin/requests/show.html.erb
+++ b/app_echo/app/views/admin/requests/show.html.erb
@@ -26,9 +26,33 @@
     <% if @request.reject_reason.present? %>
       <div class="detail-row"><span class="detail-label">Reject Reason</span><span class="detail-value"><%= @request.reject_reason %></span></div>
     <% end %>
+    <% if @request.recurring? %>
+      <div class="detail-row"><span class="detail-label">Recurring Group</span><span class="detail-value"><%= @request.recurring_group_id %></span></div>
+      <div class="detail-row"><span class="detail-label">Session</span><span class="detail-value"><%= @request.recurring_index + 1 %> of <%= @recurring_requests.size %></span></div>
+    <% end %>
     <div class="detail-row"><span class="detail-label">Created At</span><span class="detail-value"><%= @request.created_at&.strftime("%Y-%m-%d %H:%M") %></span></div>
   </div>
 
+  <% if @request.recurring? %>
+    <div class="detail-card">
+      <h2>Recurring Sessions</h2>
+      <table>
+        <thead>
+          <tr><th>#</th><th>Scheduled</th><th>State</th></tr>
+        </thead>
+        <tbody>
+          <% @recurring_requests.each do |r| %>
+            <tr>
+              <td><%= link_to "##{r.id}", admin_request_path(r) %></td>
+              <td><%= r.scheduled_at&.strftime("%Y-%m-%d %H:%M") %></td>
+              <td><span class="badge badge-<%= r.state %>"><%= r.state.humanize %></span></td>
+            </tr>
+          <% end %>
+        </tbody>
+      </table>
+    </div>
+  <% end %>
+
   <% if @request.payment %>
     <div class="detail-card">
       <h2>Payment</h2>
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
diff --git a/app_echo/spec/models/request_spec.rb b/app_echo/spec/models/request_spec.rb
index a9aece5..f6b14f4 100644
--- a/app_echo/spec/models/request_spec.rb
+++ b/app_echo/spec/models/request_spec.rb
@@ -218,5 +218,32 @@
         expect(sorted.first.scheduled_at).to be >= sorted.last.scheduled_at
       end
     end
+
+    describe ".by_recurring_group" do
+      let(:group_id) { SecureRandom.uuid }
+      let!(:recurring_request) { create(:request, recurring_group_id: group_id, recurring_index: 0) }
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
   end
 end
diff --git a/app_echo/spec/services/requests/create_recurring_service_spec.rb b/app_echo/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..022cd69
--- /dev/null
+++ b/app_echo/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,82 @@
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
+        expect(result[:success]).to be true
+        expect(result[:requests].size).to eq(5)
+      end
+
+      it "assigns a shared recurring_group_id" do
+        group_id = result[:recurring_group_id]
+        expect(group_id).to be_present
+        expect(result[:requests].map(&:recurring_group_id).uniq).to eq([group_id])
+      end
+
+      it "assigns sequential recurring_index values" do
+        expect(result[:requests].map(&:recurring_index)).to eq([0, 1, 2, 3, 4])
+      end
+
+      it "schedules each request one week apart" do
+        times = result[:requests].map(&:scheduled_at)
+        times.each_cons(2) do |a, b|
+          expect(b - a).to be_within(1.second).of(1.week)
+        end
+      end
+
+      it "uses the same amount and provider for all requests" do
+        requests = result[:requests]
+        expect(requests.map(&:amount_cents).uniq).to eq([350_000])
+        expect(requests.map(&:provider_id).uniq).to eq([provider.id])
+      end
+
+      it "creates all requests in pending state" do
+        expect(result[:requests].map(&:state).uniq).to eq(["pending"])
+      end
+
+      it "notifies the provider for each request" do
+        result
+        log = read_notification_log
+        # 3 channels (push, sms, email) x 5 requests = 15 notifications
+        expect(log.scan("event=request_created").size).to eq(15)
+      end
+    end
+
+    context "with invalid params" do
+      let(:valid_params) { { scheduled_at: base_time.iso8601, duration_minutes: nil } }
+
+      it "returns errors and creates no requests" do
+        expect { result }.not_to change(Request, :count)
+        expect(result[:success]).to be false
+        expect(result[:errors]).to be_present
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
+    end
+  end
+end
```
