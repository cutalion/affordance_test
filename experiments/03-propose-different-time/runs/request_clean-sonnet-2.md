# Experiment: 03-propose-different-time
# App: request_clean | Model: sonnet | Run: 2
# Branch: experiment/03-propose-different-time/request_clean/sonnet/run-2

---

## Claude Output

Done. Here's what was implemented:

**New state machine state:** `counter_proposed` (sits between `pending` and `confirmed`)

**New AASM events on `Request`:**
- `propose_time` — pending → counter_proposed
- `accept_counter_proposal` — counter_proposed → confirmed (updates `scheduled_at` to the proposed time)
- `decline_counter_proposal` — counter_proposed → canceled

**New DB fields:** `counter_proposed_at` (datetime), `counter_proposal_note` (text)

**New services:**
- `Requests::ProposeTimeService` — provider only, requires `proposed_at`
- `Requests::AcceptCounterProposalService` — client only
- `Requests::DeclineCounterProposalService` — client only

**New API endpoints:**
- `PATCH /api/requests/:id/propose_time` — params: `proposed_at`, optional `note`
- `PATCH /api/requests/:id/accept_counter_proposal` — client only
- `PATCH /api/requests/:id/decline_counter_proposal` — client only

**Notifications + email templates** for all three events.

---

## Git Diff

```diff
diff --git a/affordance_request_clean/app/controllers/api/requests_controller.rb b/affordance_request_clean/app/controllers/api/requests_controller.rb
index 969b32b..c41114d 100644
--- a/affordance_request_clean/app/controllers/api/requests_controller.rb
+++ b/affordance_request_clean/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject]
+    before_action :set_request, only: [:show, :confirm, :start, :complete, :cancel, :reject, :propose_time, :accept_counter_proposal, :decline_counter_proposal]
 
     def index
       requests = scoped_requests
@@ -90,6 +90,45 @@ def reject
       handle_service_result(result)
     end
 
+    def propose_time
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_at].blank?
+        return render_unprocessable(["Proposed time is required"])
+      end
+
+      result = Requests::ProposeTimeService.new(
+        request: @request,
+        provider: provider,
+        proposed_at: params[:proposed_at],
+        note: params[:note]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptCounterProposalService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
+    def decline_counter_proposal
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineCounterProposalService.new(
+        request: @request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -141,6 +180,8 @@ def request_detail_json(request)
         currency: request.currency,
         cancel_reason: request.cancel_reason,
         reject_reason: request.reject_reason,
+        counter_proposed_at: request.counter_proposed_at,
+        counter_proposal_note: request.counter_proposal_note,
         started_at: request.started_at,
         completed_at: request.completed_at,
         client_id: request.client_id,
diff --git a/affordance_request_clean/app/mailers/request_mailer.rb b/affordance_request_clean/app/mailers/request_mailer.rb
index f10345b..8815032 100644
--- a/affordance_request_clean/app/mailers/request_mailer.rb
+++ b/affordance_request_clean/app/mailers/request_mailer.rb
@@ -35,6 +35,24 @@ def request_rejected(recipient, payload)
     mail(to: recipient.email, subject: "Request ##{@request_id} rejected")
   end
 
+  def request_time_proposed(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Provider proposed a new time for request ##{@request_id}")
+  end
+
+  def counter_proposal_accepted(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Client accepted your proposed time for request ##{@request_id}")
+  end
+
+  def counter_proposal_declined(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Client declined your proposed time for request ##{@request_id}")
+  end
+
   def review_reminder(recipient, payload)
     @recipient = recipient
     @request_id = payload[:request_id]
diff --git a/affordance_request_clean/app/models/request.rb b/affordance_request_clean/app/models/request.rb
index 67cb0ca..d498a55 100644
--- a/affordance_request_clean/app/models/request.rb
+++ b/affordance_request_clean/app/models/request.rb
@@ -13,6 +13,7 @@ class Request < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :counter_proposed_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -29,12 +30,28 @@ class Request < ApplicationRecord
 
   aasm column: :state do
     state :pending, initial: true
+    state :counter_proposed
     state :confirmed
     state :in_progress
     state :completed
     state :canceled
     state :rejected
 
+    event :propose_time do
+      transitions from: :pending, to: :counter_proposed
+    end
+
+    event :accept_counter_proposal do
+      transitions from: :counter_proposed, to: :confirmed
+      after do
+        update!(scheduled_at: counter_proposed_at)
+      end
+    end
+
+    event :decline_counter_proposal do
+      transitions from: :counter_proposed, to: :canceled
+    end
+
     event :confirm do
       transitions from: :pending, to: :confirmed
     end
@@ -54,7 +71,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:pending, :confirmed], to: :canceled
+      transitions from: [:pending, :confirmed, :counter_proposed], to: :canceled
     end
 
     event :reject do
diff --git a/affordance_request_clean/app/services/requests/accept_counter_proposal_service.rb b/affordance_request_clean/app/services/requests/accept_counter_proposal_service.rb
new file mode 100644
index 0000000..886fb74
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/accept_counter_proposal_service.rb
@@ -0,0 +1,25 @@
+module Requests
+  class AcceptCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.accept_counter_proposal!
+
+      NotificationService.notify(@request.provider, :counter_proposal_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter-proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/decline_counter_proposal_service.rb b/affordance_request_clean/app/services/requests/decline_counter_proposal_service.rb
new file mode 100644
index 0000000..8d97a79
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/decline_counter_proposal_service.rb
@@ -0,0 +1,26 @@
+module Requests
+  class DeclineCounterProposalService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.cancel_reason = "Client declined counter-proposal"
+      @request.decline_counter_proposal!
+
+      NotificationService.notify(@request.provider, :counter_proposal_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline counter-proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/services/requests/propose_time_service.rb b/affordance_request_clean/app/services/requests/propose_time_service.rb
new file mode 100644
index 0000000..b9c5a1e
--- /dev/null
+++ b/affordance_request_clean/app/services/requests/propose_time_service.rb
@@ -0,0 +1,30 @@
+module Requests
+  class ProposeTimeService
+    def initialize(request:, provider:, proposed_at:, note: nil)
+      @request = request
+      @provider = provider
+      @proposed_at = proposed_at
+      @note = note
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("Proposed time is required") if @proposed_at.blank?
+
+      @request.counter_proposed_at = @proposed_at
+      @request.counter_proposal_note = @note
+      @request.propose_time!
+
+      NotificationService.notify(@request.client, :request_time_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot propose a new time for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request_clean/app/views/request_mailer/counter_proposal_accepted.text.erb b/affordance_request_clean/app/views/request_mailer/counter_proposal_accepted.text.erb
new file mode 100644
index 0000000..d113522
--- /dev/null
+++ b/affordance_request_clean/app/views/request_mailer/counter_proposal_accepted.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, the client has accepted your proposed time for request #<%= @request_id %>. The request is now confirmed.
diff --git a/affordance_request_clean/app/views/request_mailer/counter_proposal_declined.text.erb b/affordance_request_clean/app/views/request_mailer/counter_proposal_declined.text.erb
new file mode 100644
index 0000000..ea58806
--- /dev/null
+++ b/affordance_request_clean/app/views/request_mailer/counter_proposal_declined.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, the client has declined your proposed time for request #<%= @request_id %>. The request has been canceled.
diff --git a/affordance_request_clean/app/views/request_mailer/request_time_proposed.text.erb b/affordance_request_clean/app/views/request_mailer/request_time_proposed.text.erb
new file mode 100644
index 0000000..2ff2d9c
--- /dev/null
+++ b/affordance_request_clean/app/views/request_mailer/request_time_proposed.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, the provider has proposed a new time for request #<%= @request_id %>. Please log in to accept or decline the counter-proposal.
diff --git a/affordance_request_clean/config/routes.rb b/affordance_request_clean/config/routes.rb
index 06454f8..8e4a768 100644
--- a/affordance_request_clean/config/routes.rb
+++ b/affordance_request_clean/config/routes.rb
@@ -17,6 +17,9 @@
         patch :complete
         patch :cancel
         patch :reject
+        patch :propose_time
+        patch :accept_counter_proposal
+        patch :decline_counter_proposal
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request_clean/db/migrate/20260407213014_add_counter_proposal_to_requests.rb b/affordance_request_clean/db/migrate/20260407213014_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..9ffd41c
--- /dev/null
+++ b/affordance_request_clean/db/migrate/20260407213014_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :counter_proposed_at, :datetime
+    add_column :requests, :counter_proposal_note, :text
+  end
+end
diff --git a/affordance_request_clean/db/schema.rb b/affordance_request_clean/db/schema.rb
index f918f92..62e8acb 100644
--- a/affordance_request_clean/db/schema.rb
+++ b/affordance_request_clean/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_08_000001) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -73,11 +73,15 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.text "counter_note"
+    t.text "counter_proposal_note"
+    t.datetime "counter_proposed_at"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
```
