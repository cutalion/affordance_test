# Experiment: 03-propose-different-time
# App: request_clean | Model: opus | Run: 2
# Branch: experiment/03-propose-different-time/request_clean/opus/run-2

---

## Claude Output

Done. Here's what was implemented:

**New state**: `time_proposed` — entered when a provider suggests a different time

**New flow**:
1. Provider calls `PATCH /api/requests/:id/propose_new_time` with `proposed_scheduled_at` → request moves from `pending` to `time_proposed`
2. Client calls `PATCH /api/requests/:id/accept_proposed_time` → request moves to `confirmed` with `scheduled_at` updated to the proposed time
3. Client calls `PATCH /api/requests/:id/decline_proposed_time` → request returns to `pending` (client can cancel, find another provider, etc.)

**Files changed**:
- Migration adding `proposed_scheduled_at` column
- `Request` model — new `time_proposed` state, 3 new events, validation
- 3 new services: `ProposeNewTimeService`, `AcceptProposedTimeService`, `DeclineProposedTimeService`
- Routes & controller — 3 new endpoints
- Mailer — 3 new notification methods
- Factory trait `:time_proposed`
- 20 new tests (13 service + 7 request specs), all 285 tests passing

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..c11d22d 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :propose_new_time, :accept_proposed_time, :decline_proposed_time, :start, :complete, :cancel, :reject]
 
     def index
       requests = scoped_requests
@@ -42,6 +42,38 @@ def confirm
       handle_service_result(result)
     end
 
+    def propose_new_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_scheduled_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Requests::ProposeNewTimeService.new(
+        request: @request,
+        provider: provider,
+        proposed_scheduled_at: params[:proposed_scheduled_at]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_proposed_time
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptProposedTimeService.new(request: @request, client: client).call
+      handle_service_result(result)
+    end
+
+    def decline_proposed_time
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineProposedTimeService.new(request: @request, client: client).call
+      handle_service_result(result)
+    end
+
     def start
       provider = current_provider!
       return if performed?
@@ -139,6 +171,7 @@ def request_detail_json(request)
         notes: request.notes,
         amount_cents: request.amount_cents,
         currency: request.currency,
+        proposed_scheduled_at: request.proposed_scheduled_at,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
         started_at: request.started_at,
diff --git a/affordance_request_clean/app/mailers/request_mailer.rb b/affordance_request_clean/app/mailers/request_mailer.rb
index f10345b..35c5594 100644
--- a/affordance_request_clean/app/mailers/request_mailer.rb
+++ b/affordance_request_clean/app/mailers/request_mailer.rb
@@ -29,6 +29,24 @@ def request_canceled(recipient, payload)
     mail(to: recipient.email, subject: "Request ##{@request_id} canceled")
   end
 
+  def request_time_proposed(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "New time proposed for request ##{@request_id}")
+  end
+
+  def request_proposed_time_accepted(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Proposed time accepted for request ##{@request_id}")
+  end
+
+  def request_proposed_time_declined(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Proposed time declined for request ##{@request_id}")
+  end
+
   def request_rejected(recipient, payload)
     @recipient = recipient
     @request_id = payload[:request_id]
diff --git a/affordance_request_clean/app/models/request.rb b/affordance_request_clean/app/models/request.rb
index 67cb0ca..d7e6b55 100644
--- a/affordance_request_clean/app/models/request.rb
+++ b/affordance_request_clean/app/models/request.rb
@@ -13,6 +13,7 @@ class Request < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_scheduled_at, presence: true, if: -> { time_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -34,11 +35,30 @@ class Request < ApplicationRecord
     state :completed
     state :canceled
     state :rejected
+    state :time_proposed
 
     event :confirm do
       transitions from: :pending, to: :confirmed
     end
 
+    event :propose_new_time do
+      transitions from: :pending, to: :time_proposed
+    end
+
+    event :accept_proposed_time do
+      transitions from: :time_proposed, to: :confirmed
+      after do
+        update!(scheduled_at: proposed_scheduled_at, proposed_scheduled_at: nil)
+      end
+    end
+
+    event :decline_proposed_time do
+      transitions from: :time_proposed, to: :pending
+      after do
+        update!(proposed_scheduled_at: nil)
+      end
+    end
+
     event :start do
       transitions from: :confirmed, to: :in_progress
       after do
@@ -54,7 +74,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :confirmed], to: :canceled
+      transitions from: [:pending, :confirmed, :time_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/affordance_request_clean/app/services/requests/accept_proposed_time_service.rb b/affordance_request_clean/app/services/requests/accept_proposed_time_service.rb
new file mode 100644
index 0000000..f599f9f
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/accept_proposed_time_service.rb
@@ -0,0 +1,24 @@
+module Requests
+  class AcceptProposedTimeService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.accept_proposed_time!
+      NotificationService.notify(@request.provider, :request_proposed_time_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept proposed time for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/decline_proposed_time_service.rb b/affordance_request_clean/app/services/requests/decline_proposed_time_service.rb
new file mode 100644
index 0000000..17213f1
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/decline_proposed_time_service.rb
@@ -0,0 +1,24 @@
+module Requests
+  class DeclineProposedTimeService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.decline_proposed_time!
+      NotificationService.notify(@request.provider, :request_proposed_time_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline proposed time for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/propose_new_time_service.rb b/affordance_request_clean/app/services/requests/propose_new_time_service.rb
new file mode 100644
index 0000000..2b1f517
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/propose_new_time_service.rb
@@ -0,0 +1,27 @@
+module Requests
+  class ProposeNewTimeService
+    def initialize(request:, provider:, proposed_scheduled_at:)
+      @request = request
+      @provider = provider
+      @proposed_scheduled_at = proposed_scheduled_at
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_scheduled_at.blank?
+
+      @request.proposed_scheduled_at = @proposed_scheduled_at
+      @request.propose_new_time!
+      NotificationService.notify(@request.client, :request_time_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot propose new time for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..fe3e186 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -13,6 +13,9 @@
     resources :requests, only: [:index, :show, :create] do
       member do
         patch :confirm
+        patch :propose_new_time
+        patch :accept_proposed_time
+        patch :decline_proposed_time
         patch :start
         patch :complete
         patch :cancel
diff --git a/affordance_request_clean/db/migrate/20260407214003_add_proposed_scheduled_at_to_requests.rb b/affordance_request_clean/db/migrate/20260407214003_add_proposed_scheduled_at_to_requests.rb
new file mode 100644
index 0000000..a95e8f4
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260407214003_add_proposed_scheduled_at_to_requests.rb
@@ -0,0 +1,5 @@
+class AddProposedScheduledAtToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_scheduled_at, :datetime
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..0a5e332 100644
--- a/affordance_request_clean/db/schema.rb
+++ b/affordance_request_clean/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_214003) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -78,6 +78,7 @@
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
diff --git a/affordance_request_clean/spec/factories/requests.rb b/affordance_request_clean/spec/factories/requests.rb
index c63766e..cfec057 100644
--- a/affordance_request_clean/spec/factories/requests.rb
+++ b/affordance_request_clean/spec/factories/requests.rb
@@ -34,6 +34,11 @@
       reject_reason { "Cannot make it" }
     end
 
+    trait :time_proposed do
+      state { "time_proposed" }
+      proposed_scheduled_at { 5.days.from_now }
+    end
+
     trait :with_payment do
       after(:create) do |request|
         create(:payment, request: request, amount_cents: request.amount_cents, currency: request.currency)
diff --git a/affordance_request_clean/spec/requests/api/requests_spec.rb b/affordance_request_clean/spec/requests/api/requests_spec.rb
index 86b84c8..0a98ec7 100644
--- a/affordance_request_clean/spec/requests/api/requests_spec.rb
+++ b/affordance_request_clean/spec/requests/api/requests_spec.rb
@@ -166,6 +166,63 @@
     end
   end
 
+  describe "PATCH /api/requests/:id/propose_new_time" do
+    let(:request) { create(:request, client: client, provider: provider) }
+    let(:proposed_time) { 5.days.from_now.iso8601 }
+
+    it "proposes a new time as provider" do
+      patch "/api/requests/#{request.id}/propose_new_time", params: { proposed_scheduled_at: proposed_time }, headers: auth_headers(provider)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("time_proposed")
+      expect(body["proposed_scheduled_at"]).to be_present
+    end
+
+    it "returns error without proposed time" do
+      patch "/api/requests/#{request.id}/propose_new_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:unprocessable_entity)
+    end
+
+    it "returns 403 for client" do
+      patch "/api/requests/#{request.id}/propose_new_time", params: { proposed_scheduled_at: proposed_time }, headers: auth_headers(client)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/accept_proposed_time" do
+    let(:request) { create(:request, :time_proposed, client: client, provider: provider) }
+
+    it "accepts the proposed time as client" do
+      patch "/api/requests/#{request.id}/accept_proposed_time", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("confirmed")
+      expect(body["proposed_scheduled_at"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/accept_proposed_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
+  describe "PATCH /api/requests/:id/decline_proposed_time" do
+    let(:request) { create(:request, :time_proposed, client: client, provider: provider) }
+
+    it "declines the proposed time as client" do
+      patch "/api/requests/#{request.id}/decline_proposed_time", headers: auth_headers(client)
+      expect(response).to have_http_status(:ok)
+      body = JSON.parse(response.body)
+      expect(body["state"]).to eq("pending")
+      expect(body["proposed_scheduled_at"]).to be_nil
+    end
+
+    it "returns 403 for provider" do
+      patch "/api/requests/#{request.id}/decline_proposed_time", headers: auth_headers(provider)
+      expect(response).to have_http_status(:forbidden)
+    end
+  end
+
   describe "PATCH /api/requests/:id/reject" do
     let(:request) { create(:request, :confirmed, client: client, provider: provider) }
 
diff --git a/affordance_request_clean/spec/services/requests/accept_proposed_time_service_spec.rb b/affordance_request_clean/spec/services/requests/accept_proposed_time_service_spec.rb
new file mode 100644
index 0000000..d6a95bf
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/accept_proposed_time_service_spec.rb
@@ -0,0 +1,37 @@
+require "rails_helper"
+
+RSpec.describe Requests::AcceptProposedTimeService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:proposed_time) { 5.days.from_now }
+  let(:request) { create(:request, :time_proposed, client: client, provider: provider, proposed_scheduled_at: proposed_time) }
+
+  describe "#call" do
+    it "accepts the proposed time" do
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("confirmed")
+      expect(request.scheduled_at).to be_within(1.second).of(proposed_time)
+      expect(request.proposed_scheduled_at).to be_nil
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=request_proposed_time_accepted")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for pending request" do
+      pending_request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: pending_request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot accept proposed time")
+    end
+  end
+end
diff --git a/affordance_request_clean/spec/services/requests/decline_proposed_time_service_spec.rb b/affordance_request_clean/spec/services/requests/decline_proposed_time_service_spec.rb
new file mode 100644
index 0000000..82fb4e7
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/decline_proposed_time_service_spec.rb
@@ -0,0 +1,35 @@
+require "rails_helper"
+
+RSpec.describe Requests::DeclineProposedTimeService do
+  let(:client) { create(:client) }
+  let(:other_client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:request) { create(:request, :time_proposed, client: client, provider: provider) }
+
+  describe "#call" do
+    it "declines the proposed time and returns to pending" do
+      result = described_class.new(request: request, client: client).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("pending")
+      expect(request.proposed_scheduled_at).to be_nil
+    end
+
+    it "notifies the provider" do
+      described_class.new(request: request, client: client).call
+      expect(read_notification_log).to include("event=request_proposed_time_declined")
+    end
+
+    it "fails for wrong client" do
+      result = described_class.new(request: request, client: other_client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails for pending request" do
+      pending_request = create(:request, client: client, provider: provider)
+      result = described_class.new(request: pending_request, client: client).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot decline proposed time")
+    end
+  end
+end
diff --git a/affordance_request_clean/spec/services/requests/propose_new_time_service_spec.rb b/affordance_request_clean/spec/services/requests/propose_new_time_service_spec.rb
new file mode 100644
index 0000000..6449136
--- /dev/null
+++ b/affordance_request_clean/spec/services/requests/propose_new_time_service_spec.rb
@@ -0,0 +1,42 @@
+require "rails_helper"
+
+RSpec.describe Requests::ProposeNewTimeService do
+  let(:client) { create(:client) }
+  let(:provider) { create(:provider) }
+  let(:other_provider) { create(:provider) }
+  let(:request) { create(:request, client: client, provider: provider) }
+  let(:proposed_time) { 5.days.from_now }
+
+  describe "#call" do
+    it "proposes a new time for a pending request" do
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be true
+      expect(request.reload.state).to eq("time_proposed")
+      expect(request.proposed_scheduled_at).to be_within(1.second).of(proposed_time)
+    end
+
+    it "notifies the client" do
+      described_class.new(request: request, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(read_notification_log).to include("event=request_time_proposed")
+    end
+
+    it "fails for wrong provider" do
+      result = described_class.new(request: request, provider: other_provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Not your request")
+    end
+
+    it "fails without proposed time" do
+      result = described_class.new(request: request, provider: provider, proposed_scheduled_at: nil).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to eq("Proposed time is required")
+    end
+
+    it "fails for confirmed request" do
+      confirmed_request = create(:request, :confirmed, client: client, provider: provider)
+      result = described_class.new(request: confirmed_request, provider: provider, proposed_scheduled_at: proposed_time).call
+      expect(result[:success]).to be false
+      expect(result[:error]).to include("Cannot propose new time")
+    end
+  end
+end
```
