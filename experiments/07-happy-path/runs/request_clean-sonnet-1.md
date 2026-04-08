# Experiment: 07-happy-path
# App: request_clean | Model: sonnet | Run: 1

---

Here's the happy path for a **Request** (the main entity):

---

## Happy Path: Request Lifecycle

### 1. Client creates a Request (`pending`)
- Client submits scheduling details: provider, time, duration, location, notes, amount
- `CreateService` saves the Request and atomically creates a linked `Payment` (status: `pending`)
- Provider is notified: `:request_created`

### 2. Payment is held (background job)
- `PaymentHoldJob` runs periodically, finds requests scheduled within the next 24 hours with a pending payment
- `PaymentGateway.hold` puts a hold on the client's card
- Payment transitions to `held`

### 3. Provider confirms the Request (`confirmed`)
- Provider calls `ConfirmService`
- Request transitions: `pending → confirmed`
- Client is notified: `:request_confirmed`

### 4. Provider starts the Request (`in_progress`)
- Provider calls `StartService`
- Request transitions: `confirmed → in_progress`
- `started_at` is recorded
- Client is notified: `:request_started`

### 5. Provider completes the Request (`completed`)
- Provider calls `CompleteService`
- Request transitions: `in_progress → completed`
- `completed_at` is recorded
- If payment is held, `PaymentGateway.charge` captures the funds
- Both client and provider notified: `:request_completed`

### 6. Review reminders (background job)
- `ReviewReminderJob` runs periodically
- 24–48 hours after completion, it reminds any party who hasn't left a review yet

---

**State chain:** `pending → confirmed → in_progress → completed`

The provider drives every transition; the client is a passive participant who gets notified at each step.
