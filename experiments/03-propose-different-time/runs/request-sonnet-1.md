# Experiment: 03-propose-different-time
# App: request | Model: sonnet | Run: 1
# Branch: experiment/03-propose-different-time/request/sonnet/run-1

---

## Claude Output

Done. Here's a summary of what was implemented:

**New state:** `counter_proposed` added to the request state machine.

**Flow:**
1. Provider: `PATCH /api/requests/:id/counter_propose` with `proposed_at` (required) and `note` (optional) → state: `created` → `counter_proposed`
2. Client: `PATCH /api/requests/:id/accept_counter` → state: `counter_proposed` → `accepted` (also updates `scheduled_at` to the proposed time)
3. Client: `PATCH /api/requests/:id/decline_counter` → state: `counter_proposed` → `declined`

**Also:** Cancel is allowed from `counter_proposed` state. Email notifications are sent at each step. The `proposed_at` and `counter_proposal_note` fields appear in the request detail JSON response.

---

## Git Diff

```diff
diff --git a/affordance_request/app/controllers/api/requests_controller.rb b/affordance_request/app/controllers/api/requests_controller.rb
index deef66b..038b9f8 100644
--- a/affordance_request/app/controllers/api/requests_controller.rb
+++ b/affordance_request/app/controllers/api/requests_controller.rb
@@ -1,6 +1,6 @@
 module Api
   class RequestsController < BaseController
-    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject]
+    before_action :set_request, only: [:show, :accept, :decline, :start, :fulfill, :cancel, :reject, :counter_propose, :accept_counter, :decline_counter]
 
     def index
       requests = scoped_requests
@@ -118,6 +118,45 @@ def reject
       handle_service_result(result)
     end
 
+    def counter_propose
+      provider = current_provider!
+      return if performed?
+
+      if params[:proposed_at].blank?
+        return render_unprocessable(["proposed_at is required"])
+      end
+
+      result = Requests::CounterProposeService.new(
+        request: @the_request,
+        provider: provider,
+        proposed_at: params[:proposed_at],
+        note: params[:note]
+      ).call
+      handle_service_result(result)
+    end
+
+    def accept_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::AcceptCounterService.new(
+        request: @the_request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
+    def decline_counter
+      client = current_client!
+      return if performed?
+
+      result = Requests::DeclineCounterService.new(
+        request: @the_request,
+        client: client
+      ).call
+      handle_service_result(result)
+    end
+
     private
 
     def set_request
@@ -169,6 +208,8 @@ def request_detail_json(req)
         currency: req.currency,
         cancel_reason: req.cancel_reason,
         reject_reason: req.reject_reason,
+        proposed_at: req.proposed_at,
+        counter_proposal_note: req.counter_proposal_note,
         started_at: req.started_at,
         completed_at: req.completed_at,
         client_id: req.client_id,
diff --git a/affordance_request/app/mailers/request_mailer.rb b/affordance_request/app/mailers/request_mailer.rb
index 51ef746..66bc5c4 100644
--- a/affordance_request/app/mailers/request_mailer.rb
+++ b/affordance_request/app/mailers/request_mailer.rb
@@ -47,6 +47,24 @@ def request_rejected(recipient, payload)
     mail(to: recipient.email, subject: "Request ##{@request_id} rejected")
   end
 
+  def request_counter_proposed(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - provider proposed a different time")
+  end
+
+  def request_counter_accepted(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - counter proposal accepted")
+  end
+
+  def request_counter_declined(recipient, payload)
+    @recipient = recipient
+    @request_id = payload[:request_id]
+    mail(to: recipient.email, subject: "Request ##{@request_id} - counter proposal declined")
+  end
+
   def review_reminder(recipient, payload)
     @recipient = recipient
     @request_id = payload[:request_id]
diff --git a/affordance_request/app/models/request.rb b/affordance_request/app/models/request.rb
index 1c6cff4..b110276 100644
--- a/affordance_request/app/models/request.rb
+++ b/affordance_request/app/models/request.rb
@@ -13,6 +13,7 @@ class Request < ApplicationRecord
   validates :currency, presence: true
   validates :cancel_reason, presence: true, if: -> { canceled? }
   validates :reject_reason, presence: true, if: -> { rejected? }
+  validates :proposed_at, presence: true, if: -> { counter_proposed? }
 
   scope :upcoming, -> { where("scheduled_at > ?", Time.current) }
   scope :past, -> { where("scheduled_at <= ?", Time.current) }
@@ -30,6 +31,7 @@ class Request < ApplicationRecord
   aasm column: :state do
     state :created, initial: true
     state :created_accepted
+    state :counter_proposed
     state :accepted
     state :started
     state :fulfilled
@@ -50,6 +52,18 @@ class Request < ApplicationRecord
       transitions from: :created, to: :missed
     end
 
+    event :propose_counter do
+      transitions from: :created, to: :counter_proposed
+    end
+
+    event :accept_counter do
+      transitions from: :counter_proposed, to: :accepted
+    end
+
+    event :decline_counter do
+      transitions from: :counter_proposed, to: :declined
+    end
+
     event :start do
       transitions from: [:accepted, :created_accepted], to: :started
       after do
@@ -65,7 +79,7 @@ class Request < ApplicationRecord
     end
 
     event :cancel do
-      transitions from: [:created, :accepted, :created_accepted], to: :canceled
+      transitions from: [:created, :counter_proposed, :accepted, :created_accepted], to: :canceled
     end
 
     event :reject do
diff --git a/affordance_request/app/services/requests/accept_counter_service.rb b/affordance_request/app/services/requests/accept_counter_service.rb
new file mode 100644
index 0000000..e5e091e
--- /dev/null
+++ b/affordance_request/app/services/requests/accept_counter_service.rb
@@ -0,0 +1,26 @@
+module Requests
+  class AcceptCounterService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.scheduled_at = @request.proposed_at
+      @request.accept_counter!
+
+      NotificationService.notify(@request.provider, :request_counter_accepted, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot accept counter proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/app/services/requests/counter_propose_service.rb b/affordance_request/app/services/requests/counter_propose_service.rb
new file mode 100644
index 0000000..4883ee6
--- /dev/null
+++ b/affordance_request/app/services/requests/counter_propose_service.rb
@@ -0,0 +1,30 @@
+module Requests
+  class CounterProposeService
+    def initialize(request:, provider:, proposed_at:, note: nil)
+      @request = request
+      @provider = provider
+      @proposed_at = proposed_at
+      @note = note
+    end
+
+    def call
+      return error("Not your request") unless @request.provider_id == @provider.id
+      return error("proposed_at is required") if @proposed_at.blank?
+
+      @request.proposed_at = @proposed_at
+      @request.counter_proposal_note = @note
+      @request.propose_counter!
+
+      NotificationService.notify(@request.client, :request_counter_proposed, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot propose a counter offer for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/app/services/requests/decline_counter_service.rb b/affordance_request/app/services/requests/decline_counter_service.rb
new file mode 100644
index 0000000..8da24e3
--- /dev/null
+++ b/affordance_request/app/services/requests/decline_counter_service.rb
@@ -0,0 +1,25 @@
+module Requests
+  class DeclineCounterService
+    def initialize(request:, client:)
+      @request = request
+      @client = client
+    end
+
+    def call
+      return error("Not your request") unless @request.client_id == @client.id
+
+      @request.decline_counter!
+
+      NotificationService.notify(@request.provider, :request_counter_declined, request_id: @request.id)
+      { success: true, request: @request }
+    rescue AASM::InvalidTransition
+      error("Cannot decline counter proposal for request in #{@request.state} state")
+    end
+
+    private
+
+    def error(message)
+      { success: false, error: message }
+    end
+  end
+end
diff --git a/affordance_request/app/views/request_mailer/request_counter_accepted.text.erb b/affordance_request/app/views/request_mailer/request_counter_accepted.text.erb
new file mode 100644
index 0000000..49fd934
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_counter_accepted.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, the client has accepted your counter proposal for request #<%= @request_id %>. The request is now accepted at the proposed time.
diff --git a/affordance_request/app/views/request_mailer/request_counter_declined.text.erb b/affordance_request/app/views/request_mailer/request_counter_declined.text.erb
new file mode 100644
index 0000000..d55e15d
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_counter_declined.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, the client has declined your counter proposal for request #<%= @request_id %>. The request is now closed.
diff --git a/affordance_request/app/views/request_mailer/request_counter_proposed.text.erb b/affordance_request/app/views/request_mailer/request_counter_proposed.text.erb
new file mode 100644
index 0000000..cc6abd0
--- /dev/null
+++ b/affordance_request/app/views/request_mailer/request_counter_proposed.text.erb
@@ -0,0 +1 @@
+Hello <%= @recipient.name %>, the provider has proposed a different time for request #<%= @request_id %>. Please review the new time and accept or decline the counter proposal.
diff --git a/affordance_request/config/routes.rb b/affordance_request/config/routes.rb
index 5412c66..79ab046 100644
--- a/affordance_request/config/routes.rb
+++ b/affordance_request/config/routes.rb
@@ -21,6 +21,9 @@
         patch :fulfill
         patch :cancel
         patch :reject
+        patch :counter_propose
+        patch :accept_counter
+        patch :decline_counter
       end
       resources :reviews, only: [:index, :create]
     end
diff --git a/affordance_request/db/migrate/20260407112329_add_counter_proposal_to_requests.rb b/affordance_request/db/migrate/20260407112329_add_counter_proposal_to_requests.rb
new file mode 100644
index 0000000..5212e56
--- /dev/null
+++ b/affordance_request/db/migrate/20260407112329_add_counter_proposal_to_requests.rb
@@ -0,0 +1,6 @@
+class AddCounterProposalToRequests < ActiveRecord::Migration[8.1]
+  def change
+    add_column :requests, :proposed_at, :datetime
+    add_column :requests, :counter_proposal_note, :string
+  end
+end
diff --git a/affordance_request/db/schema.rb b/affordance_request/db/schema.rb
index 18c568a..3ef90d4 100644
--- a/affordance_request/db/schema.rb
+++ b/affordance_request/db/schema.rb
@@ -10,7 +10,7 @@
 #
 # It's strongly recommended that you check this file into your version control system.
 
-ActiveRecord::Schema[8.1].define(version: 2026_04_06_192657) do
+ActiveRecord::Schema[8.1].define(version: 2026_04_07_112329) do
   create_table "cards", force: :cascade do |t|
     t.string "brand", null: false
     t.integer "client_id", null: false
@@ -36,6 +36,28 @@
     t.index ["email"], name: "index_clients_on_email", unique: true
   end
 
+  create_table "orders", force: :cascade do |t|
+    t.integer "amount_cents", null: false
+    t.text "cancel_reason"
+    t.integer "client_id", null: false
+    t.datetime "completed_at"
+    t.datetime "created_at", null: false
+    t.string "currency", default: "RUB", null: false
+    t.integer "duration_minutes", null: false
+    t.string "location"
+    t.text "notes"
+    t.integer "provider_id", null: false
+    t.text "reject_reason"
+    t.datetime "scheduled_at", null: false
+    t.datetime "started_at"
+    t.string "state", default: "pending", null: false
+    t.datetime "updated_at", null: false
+    t.index ["client_id"], name: "index_orders_on_client_id"
+    t.index ["provider_id"], name: "index_orders_on_provider_id"
+    t.index ["scheduled_at"], name: "index_orders_on_scheduled_at"
+    t.index ["state"], name: "index_orders_on_state"
+  end
+
   create_table "payments", force: :cascade do |t|
     t.integer "amount_cents", null: false
     t.integer "card_id"
@@ -73,11 +95,14 @@
     t.text "cancel_reason"
     t.integer "client_id", null: false
     t.datetime "completed_at"
+    t.string "counter_proposal_note"
     t.datetime "created_at", null: false
     t.string "currency", default: "RUB", null: false
     t.integer "duration_minutes", null: false
     t.string "location"
     t.text "notes"
+    t.datetime "proposed_at"
+    t.datetime "proposed_scheduled_at"
     t.integer "provider_id", null: false
     t.text "reject_reason"
     t.datetime "scheduled_at", null: false
@@ -104,6 +129,8 @@
   end
 
   add_foreign_key "cards", "clients"
+  add_foreign_key "orders", "clients"
+  add_foreign_key "orders", "providers"
   add_foreign_key "payments", "cards"
   add_foreign_key "payments", "requests"
   add_foreign_key "requests", "clients"
```
