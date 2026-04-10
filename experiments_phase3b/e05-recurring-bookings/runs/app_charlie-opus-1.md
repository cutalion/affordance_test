# Experiment: e05-recurring-bookings
# App: app_charlie | Model: opus | Run: 1
# Branch: debt_experiment/e05-recurring-bookings/app_charlie/opus/run-1

---

## Claude Output

All verified. 115 tests pass, 0 failures. Here's a summary of what was implemented:

## Recurring Weekly Bookings

**New endpoint:** `POST /api/requests/recurring` — creates 5 weekly booking requests in a single call.

**Changes made:**

| File | Change |
|---|---|
| `db/migrate/..._add_recurring_group_id_to_requests.rb` | New migration: adds `recurring_group_id` string column + index |
| `app/models/request.rb` | Added `.recurring_group(id)` scope |
| `app/services/requests/create_recurring_service.rb` | New service: creates 5 requests in a transaction, 1 week apart, linked by UUID |
| `app/controllers/api/requests_controller.rb` | Added `recurring` action, added `recurring_group_id` to JSON responses |
| `config/routes.rb` | Added `post :recurring` collection route |
| `spec/services/requests/create_recurring_service_spec.rb` | 8 tests covering happy path + invalid params |
| `spec/models/request_spec.rb` | 1 test for the recurring_group scope |
| `spec/factories/requests.rb` | Added `:recurring` trait |

**How it works:** Client sends the same params as a regular booking request to `/api/requests/recurring`. The service creates 5 `Request` records in a DB transaction — the first at `scheduled_at`, then +7, +14, +21, +28 days. All share a `recurring_group_id` UUID. Each request has its own independent lifecycle (can be accepted/declined/cancelled individually). The provider is notified for each one.

---

## Git Diff

```diff
diff --git a/app_charlie/app/controllers/api/requests_controller.rb b/app_charlie/app/controllers/api/requests_controller.rb
index 7c11775..e81aba1 100644
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
+        render json: { requests: result[:requests].map { |r| request_detail_json(r) } }, status: :created
+      else
+        render_unprocessable(result[:errors].full_messages)
+      end
+    end
+
     def accept
       provider = current_provider!
       return if performed?
@@ -141,7 +161,8 @@ def request_summary_json(request)
         amount_cents: request.amount_cents,
         currency: request.currency,
         client_id: request.client_id,
-        provider_id: request.provider_id
+        provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id
       }
     end
 
@@ -164,6 +185,7 @@ def request_detail_json(request)
         completed_at: request.completed_at,
         client_id: request.client_id,
         provider_id: request.provider_id,
+        recurring_group_id: request.recurring_group_id,
         payment: request.payment ? {
           id: request.payment.id,
           status: request.payment.status,
diff --git a/app_charlie/app/models/request.rb b/app_charlie/app/models/request.rb
index 4a4d28a..edc8f3b 100644
--- a/app_charlie/app/models/request.rb
+++ b/app_charlie/app/models/request.rb
@@ -27,6 +27,7 @@ class Request < ApplicationRecord
     scope
   }
   scope :sorted, -> { order(scheduled_at: :desc) }
+  scope :recurring_group, ->(group_id) { where(recurring_group_id: group_id) }
 
   aasm column: :state do
     state :pending, initial: true
diff --git a/app_charlie/app/services/requests/create_recurring_service.rb b/app_charlie/app/services/requests/create_recurring_service.rb
new file mode 100644
index 0000000..0c734dc
--- /dev/null
+++ b/app_charlie/app/services/requests/create_recurring_service.rb
@@ -0,0 +1,52 @@
+module Requests
+  class CreateRecurringService
+    RECURRENCE_COUNT = 5
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      group_id = SecureRandom.uuid
+      requests = []
+
+      raw = @params[:scheduled_at]
+      base_time = case raw
+                  when String then Time.parse(raw)
+                  when nil then nil
+                  else raw
+                  end
+
+      Request.transaction do
+        RECURRENCE_COUNT.times do |i|
+          request = Request.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: base_time && (base_time + i.weeks),
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB",
+            recurring_group_id: group_id
+          )
+          requests << request
+        end
+      end
+
+      requests.each do |request|
+        NotificationService.notify(@provider, :request_created, request_id: request.id)
+      end
+
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    rescue ArgumentError, TypeError
+      errors = ActiveModel::Errors.new(Request.new)
+      errors.add(:scheduled_at, "is invalid")
+      { success: false, errors: errors }
+    end
+  end
+end
diff --git a/app_charlie/config/routes.rb b/app_charlie/config/routes.rb
index e317a7f..0f4754d 100644
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
diff --git a/app_charlie/db/migrate/20260410082342_add_recurring_group_id_to_requests.rb b/app_charlie/db/migrate/20260410082342_add_recurring_group_id_to_requests.rb
new file mode 100644
index 0000000..af3548d
--- /dev/null
+++ b/app_charlie/db/migrate/20260410082342_add_recurring_group_id_to_requests.rb
@@ -0,0 +1,6 @@
+class AddRecurringGroupIdToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :recurring_group_id, :string
+    add_index :requests, :recurring_group_id
+  end
+end
diff --git a/app_charlie/db/schema.rb b/app_charlie/db/schema.rb
index 22596a1..fabf622 100644
--- a/app_charlie/db/schema.rb
+++ b/app_charlie/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_08_140805) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_10_082342) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -82,6 +82,7 @@
     t.string "location"
     t.text "notes"
     t.integer "provider_id", null: false
+    t.string "recurring_group_id"
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
     t.datetime "started_at"
@@ -89,6 +90,7 @@
     t.datetime "updated_at", null: false
     t.index ["client_id"], name: "index_requests_on_client_id"
     t.index ["provider_id"], name: "index_requests_on_provider_id"
+    t.index ["recurring_group_id"], name: "index_requests_on_recurring_group_id"
     t.index ["scheduled_at"], name: "index_requests_on_scheduled_at"
     t.index ["state"], name: "index_requests_on_state"
   end
diff --git a/app_charlie/docs/superpowers/plans/2026-04-10-recurring-bookings.md b/app_charlie/docs/superpowers/plans/2026-04-10-recurring-bookings.md
new file mode 100644
index 0000000..be9721c
--- /dev/null
+++ b/app_charlie/docs/superpowers/plans/2026-04-10-recurring-bookings.md
@@ -0,0 +1,408 @@
+# Recurring Weekly Bookings Implementation Plan
+
+> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
+
+**Goal:** Allow clients to create 5 weekly recurring bookings with the same provider, time, and parameters in a single API call.
+
+**Architecture:** Add a nullable `recurring_group_id` (string UUID) column to `requests`. A new `Requests::CreateRecurringService` creates 5 requests in a transaction, each scheduled 1 week apart. A new `POST /api/requests/recurring` endpoint exposes this to clients. Each request is independent after creation.
+
+**Tech Stack:** Rails 8.1, SQLite, RSpec, FactoryBot, AASM
+
+---
+
+## File Structure
+
+| File | Action | Responsibility |
+|------|--------|----------------|
+| `db/migrate/TIMESTAMP_add_recurring_group_id_to_requests.rb` | Create | Add `recurring_group_id` column + index |
+| `app/models/request.rb` | Modify | Add `recurring_group` scope, expose field |
+| `app/services/requests/create_recurring_service.rb` | Create | Orchestrate creation of 5 weekly requests |
+| `app/controllers/api/requests_controller.rb` | Modify | Add `recurring` action, add field to JSON |
+| `config/routes.rb` | Modify | Add `recurring` collection route |
+| `spec/services/requests/create_recurring_service_spec.rb` | Create | Service tests |
+| `spec/factories/requests.rb` | Modify | Add `recurring` trait |
+
+---
+
+### Task 1: Migration — add `recurring_group_id` to requests
+
+**Files:**
+- Create: `db/migrate/TIMESTAMP_add_recurring_group_id_to_requests.rb`
+
+- [ ] **Step 1: Generate the migration**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bin/rails generate migration AddRecurringGroupIdToRequests recurring_group_id:string
+```
+
+- [ ] **Step 2: Edit migration to add index**
+
+The generated migration should look like this (edit if needed):
+
+```ruby
+class AddRecurringGroupIdToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :recurring_group_id, :string
+    add_index :requests, :recurring_group_id
+  end
+end
+```
+
+- [ ] **Step 3: Run the migration**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bin/rails db:migrate
+```
+
+Expected: Migration runs successfully, `db/schema.rb` updated with new column.
+
+- [ ] **Step 4: Verify schema**
+
+Check `db/schema.rb` contains `t.string "recurring_group_id"` in the `requests` table.
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add db/migrate/*_add_recurring_group_id_to_requests.rb db/schema.rb
+git commit -m "feat: add recurring_group_id column to requests"
+```
+
+---
+
+### Task 2: Model — add recurring scope and factory trait
+
+**Files:**
+- Modify: `app/models/request.rb` (add scope around line 28)
+- Modify: `spec/factories/requests.rb` (add trait)
+
+- [ ] **Step 1: Write failing test for recurring_group scope**
+
+Create a temporary test to verify the scope works. Add to a new describe block. We'll test this through the service spec later, but verify the scope in isolation first.
+
+Open `spec/models/request_spec.rb` and add at the end (before final `end`):
+
+```ruby
+describe ".recurring_group" do
+  it "returns requests sharing the same recurring_group_id" do
+    group_id = "test-group-123"
+    r1 = create(:request, recurring_group_id: group_id)
+    r2 = create(:request, recurring_group_id: group_id)
+    create(:request, recurring_group_id: nil)
+    create(:request, recurring_group_id: "other-group")
+
+    result = Request.recurring_group(group_id)
+    expect(result).to contain_exactly(r1, r2)
+  end
+end
+```
+
+- [ ] **Step 2: Run the test to verify it fails**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bundle exec rspec spec/models/request_spec.rb -e "recurring_group"
+```
+
+Expected: FAIL — `NoMethodError: undefined method 'recurring_group'`
+
+- [ ] **Step 3: Add scope to Request model**
+
+In `app/models/request.rb`, after the `scope :sorted` line (line 29), add:
+
+```ruby
+scope :recurring_group, ->(group_id) { where(recurring_group_id: group_id) }
+```
+
+- [ ] **Step 4: Run the test to verify it passes**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bundle exec rspec spec/models/request_spec.rb -e "recurring_group"
+```
+
+Expected: PASS
+
+- [ ] **Step 5: Add recurring trait to factory**
+
+In `spec/factories/requests.rb`, add after the `:rejected` trait:
+
+```ruby
+trait :recurring do
+  recurring_group_id { SecureRandom.uuid }
+end
+```
+
+- [ ] **Step 6: Commit**
+
+```bash
+git add app/models/request.rb spec/models/request_spec.rb spec/factories/requests.rb
+git commit -m "feat: add recurring_group scope and factory trait"
+```
+
+---
+
+### Task 3: Service — CreateRecurringService
+
+**Files:**
+- Create: `app/services/requests/create_recurring_service.rb`
+- Create: `spec/services/requests/create_recurring_service_spec.rb`
+
+- [ ] **Step 1: Write failing tests**
+
+Create `spec/services/requests/create_recurring_service_spec.rb`:
+
+```ruby
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now }
+  let(:params) do
+    {
+      scheduled_at: scheduled_at,
+      duration_minutes: 60,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 200_000,
+      currency: "RUB"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: params).call }
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
+      end
+
+      it "schedules requests one week apart" do
+        requests = result[:requests].sort_by(&:scheduled_at)
+        expect(requests[0].scheduled_at).to be_within(1.second).of(scheduled_at)
+        expect(requests[1].scheduled_at).to be_within(1.second).of(scheduled_at + 7.days)
+        expect(requests[2].scheduled_at).to be_within(1.second).of(scheduled_at + 14.days)
+        expect(requests[3].scheduled_at).to be_within(1.second).of(scheduled_at + 21.days)
+        expect(requests[4].scheduled_at).to be_within(1.second).of(scheduled_at + 28.days)
+      end
+
+      it "assigns the same recurring_group_id to all requests" do
+        requests = result[:requests]
+        group_id = requests.first.recurring_group_id
+        expect(group_id).to be_present
+        expect(requests).to all(have_attributes(recurring_group_id: group_id))
+      end
+
+      it "sets the same attributes on all requests" do
+        requests = result[:requests]
+        requests.each do |req|
+          expect(req.client).to eq(client)
+          expect(req.provider).to eq(provider)
+          expect(req.duration_minutes).to eq(60)
+          expect(req.location).to eq("123 Main St")
+          expect(req.amount_cents).to eq(200_000)
+          expect(req.currency).to eq("RUB")
+          expect(req.state).to eq("pending")
+        end
+      end
+
+      it "notifies the provider for each request" do
+        result
+        log = read_notification_log
+        expect(log.scan("event=request_created").count).to eq(5)
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
+      it "creates no requests" do
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+  end
+end
+```
+
+- [ ] **Step 2: Run tests to verify they fail**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bundle exec rspec spec/services/requests/create_recurring_service_spec.rb
+```
+
+Expected: FAIL — `NameError: uninitialized constant Requests::CreateRecurringService`
+
+- [ ] **Step 3: Implement the service**
+
+Create `app/services/requests/create_recurring_service.rb`:
+
+```ruby
+module Requests
+  class CreateRecurringService
+    RECURRENCE_COUNT = 5
+
+    def initialize(client:, provider:, params:)
+      @client = client
+      @provider = provider
+      @params = params
+    end
+
+    def call
+      group_id = SecureRandom.uuid
+      requests = []
+
+      Request.transaction do
+        RECURRENCE_COUNT.times do |i|
+          request = Request.create!(
+            client: @client,
+            provider: @provider,
+            scheduled_at: Time.parse(@params[:scheduled_at].to_s) + i.weeks,
+            duration_minutes: @params[:duration_minutes],
+            location: @params[:location],
+            notes: @params[:notes],
+            amount_cents: @params[:amount_cents],
+            currency: @params[:currency] || "RUB",
+            recurring_group_id: group_id
+          )
+          requests << request
+        end
+      end
+
+      requests.each do |request|
+        NotificationService.notify(@provider, :request_created, request_id: request.id)
+      end
+
+      { success: true, requests: requests }
+    rescue ActiveRecord::RecordInvalid => e
+      { success: false, errors: e.record.errors }
+    end
+  end
+end
+```
+
+- [ ] **Step 4: Run tests to verify they pass**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bundle exec rspec spec/services/requests/create_recurring_service_spec.rb
+```
+
+Expected: All tests PASS
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add app/services/requests/create_recurring_service.rb spec/services/requests/create_recurring_service_spec.rb
+git commit -m "feat: add CreateRecurringService for weekly bookings"
+```
+
+---
+
+### Task 4: Route and Controller — recurring endpoint
+
+**Files:**
+- Modify: `config/routes.rb` (add collection route)
+- Modify: `app/controllers/api/requests_controller.rb` (add action + JSON field)
+
+- [ ] **Step 1: Add the route**
+
+In `config/routes.rb`, inside the `resources :requests` block, add a collection route. Change:
+
+```ruby
+resources :requests, only: [:index, :show, :create] do
+  member do
+```
+
+To:
+
+```ruby
+resources :requests, only: [:index, :show, :create] do
+  collection do
+    post :recurring
+  end
+  member do
+```
+
+- [ ] **Step 2: Add `recurring_group_id` to JSON serialization**
+
+In `app/controllers/api/requests_controller.rb`, add `recurring_group_id` to both `request_summary_json` and `request_detail_json`.
+
+In `request_summary_json`, add after `provider_id`:
+
+```ruby
+recurring_group_id: request.recurring_group_id
+```
+
+In `request_detail_json`, add after `provider_id`:
+
+```ruby
+recurring_group_id: request.recurring_group_id,
+```
+
+- [ ] **Step 3: Add the `recurring` action**
+
+In `app/controllers/api/requests_controller.rb`, add after the `create` method:
+
+```ruby
+def recurring
+  client = current_client!
+  return if performed?
+
+  provider = Provider.find_by(id: params[:provider_id])
+  return render_not_found unless provider
+
+  result = Requests::CreateRecurringService.new(
+    client: client,
+    provider: provider,
+    params: request_params
+  ).call
+
+  if result[:success]
+    render json: { requests: result[:requests].map { |r| request_detail_json(r) } }, status: :created
+  else
+    render_unprocessable(result[:errors].full_messages)
+  end
+end
+```
+
+- [ ] **Step 4: Run the full test suite**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bundle exec rspec
+```
+
+Expected: All tests PASS
+
+- [ ] **Step 5: Commit**
+
+```bash
+git add config/routes.rb app/controllers/api/requests_controller.rb
+git commit -m "feat: add POST /api/requests/recurring endpoint"
+```
+
+---
+
+### Task 5: Final verification
+
+- [ ] **Step 1: Run full test suite**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bundle exec rspec
+```
+
+Expected: All tests PASS, no regressions.
+
+- [ ] **Step 2: Verify routes**
+
+```bash
+cd /home/cutalion/code/affordance_test/app_charlie && bin/rails routes | grep recurring
+```
+
+Expected: Shows `recurring_requests POST /api/requests/recurring(.:format) api/requests#recurring`
diff --git a/app_charlie/docs/superpowers/specs/2026-04-10-recurring-bookings-design.md b/app_charlie/docs/superpowers/specs/2026-04-10-recurring-bookings-design.md
new file mode 100644
index 0000000..a503887
--- /dev/null
+++ b/app_charlie/docs/superpowers/specs/2026-04-10-recurring-bookings-design.md
@@ -0,0 +1,49 @@
+# Recurring Weekly Bookings
+
+## Summary
+
+Add the ability for clients to create recurring weekly bookings: 5 sessions with the same provider at the same time slot, each one week apart.
+
+## Architecture
+
+### Data Model
+
+Add a nullable `recurring_group_id` (string) column to the `requests` table. Requests that belong to a recurring series share the same group ID. Non-recurring requests have `NULL` for this field.
+
+The group ID is a SecureRandom UUID generated at creation time. No separate `recurring_groups` table is needed since each request is independently managed after creation.
+
+### Service
+
+`Requests::CreateRecurringService` — accepts the same params as `CreateService` plus uses `scheduled_at` as the anchor. Creates 5 requests in a DB transaction:
+
+- Week 1: `scheduled_at`
+- Week 2: `scheduled_at + 7.days`
+- Week 3: `scheduled_at + 14.days`
+- Week 4: `scheduled_at + 21.days`
+- Week 5: `scheduled_at + 28.days`
+
+All 5 share the same `recurring_group_id`, provider, client, location, duration, amount, currency, and notes. Each request is created in `pending` state with its own lifecycle. The provider is notified once per request.
+
+If any request fails validation, the entire batch rolls back.
+
+### API
+
+`POST /api/requests/recurring` — client-only endpoint. Accepts the same params as `POST /api/requests` (provider_id, scheduled_at, duration_minutes, location, notes, amount_cents, currency).
+
+Response: `201 Created` with `{ requests: [...] }` array of 5 request detail objects.
+
+### Model Changes
+
+- Add `recurring_group_id` column to `requests`
+- Add `scope :recurring_group` to `Request` model
+- Expose `recurring_group_id` in JSON serialization
+
+## Files Changed
+
+1. `db/migrate/..._add_recurring_group_id_to_requests.rb` — migration
+2. `app/services/requests/create_recurring_service.rb` — new service
+3. `app/models/request.rb` — add scope
+4. `app/controllers/api/requests_controller.rb` — add `recurring` action + JSON field
+5. `config/routes.rb` — add route
+6. `spec/services/requests/create_recurring_service_spec.rb` — service tests
+7. `spec/factories/requests.rb` — add recurring trait
diff --git a/app_charlie/spec/factories/requests.rb b/app_charlie/spec/factories/requests.rb
index dad8264..6047d1d 100644
--- a/app_charlie/spec/factories/requests.rb
+++ b/app_charlie/spec/factories/requests.rb
@@ -47,6 +47,10 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :recurring do
+      recurring_group_id { SecureRandom.uuid }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/app_charlie/spec/models/request_spec.rb b/app_charlie/spec/models/request_spec.rb
index a9aece5..59906a3 100644
--- a/app_charlie/spec/models/request_spec.rb
+++ b/app_charlie/spec/models/request_spec.rb
@@ -218,5 +218,18 @@
         expect(sorted.first.scheduled_at).to be >= sorted.last.scheduled_at
       end
     end
+
+    describe ".recurring_group" do
+      it "returns requests sharing the same recurring_group_id" do
+        group_id = "test-group-123"
+        r1 = create(:request, recurring_group_id: group_id)
+        r2 = create(:request, recurring_group_id: group_id)
+        create(:request, recurring_group_id: nil)
+        create(:request, recurring_group_id: "other-group")
+
+        result = Request.recurring_group(group_id)
+        expect(result).to contain_exactly(r1, r2)
+      end
+    end
   end
 end
diff --git a/app_charlie/spec/services/requests/create_recurring_service_spec.rb b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
new file mode 100644
index 0000000..f1a41ba
--- /dev/null
+++ b/app_charlie/spec/services/requests/create_recurring_service_spec.rb
@@ -0,0 +1,82 @@
+require "rails_helper"
+
+RSpec.describe Requests::CreateRecurringService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:scheduled_at) { 3.days.from_now }
+  let(:params) do
+    {
+      scheduled_at: scheduled_at,
+      duration_minutes: 60,
+      location: "123 Main St",
+      notes: "Weekly session",
+      amount_cents: 200_000,
+      currency: "RUB"
+    }
+  end
+
+  subject(:result) { described_class.new(client: client, provider: provider, params: params).call }
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
+      end
+
+      it "schedules requests one week apart" do
+        requests = result[:requests].sort_by(&:scheduled_at)
+        expect(requests[0].scheduled_at).to be_within(1.second).of(scheduled_at)
+        expect(requests[1].scheduled_at).to be_within(1.second).of(scheduled_at + 7.days)
+        expect(requests[2].scheduled_at).to be_within(1.second).of(scheduled_at + 14.days)
+        expect(requests[3].scheduled_at).to be_within(1.second).of(scheduled_at + 21.days)
+        expect(requests[4].scheduled_at).to be_within(1.second).of(scheduled_at + 28.days)
+      end
+
+      it "assigns the same recurring_group_id to all requests" do
+        requests = result[:requests]
+        group_id = requests.first.recurring_group_id
+        expect(group_id).to be_present
+        expect(requests).to all(have_attributes(recurring_group_id: group_id))
+      end
+
+      it "sets the same attributes on all requests" do
+        requests = result[:requests]
+        requests.each do |req|
+          expect(req.client).to eq(client)
+          expect(req.provider).to eq(provider)
+          expect(req.duration_minutes).to eq(60)
+          expect(req.location).to eq("123 Main St")
+          expect(req.amount_cents).to eq(200_000)
+          expect(req.currency).to eq("RUB")
+          expect(req.state).to eq("pending")
+        end
+      end
+
+      it "notifies the provider for each request" do
+        requests = result[:requests]
+        log = read_notification_log
+        requests.each do |req|
+          expect(log).to include("request_id=#{req.id}")
+        end
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
+      it "creates no requests" do
+        expect { result }.not_to change(Request, :count)
+      end
+    end
+  end
+end
```
