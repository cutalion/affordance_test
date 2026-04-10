# Experiment: 07-happy-path
# App: request_clean | Model: sonnet | Run: 2

---

Here's the happy path for a **Request** (the main entity — a babysitting booking between a client and provider):

---

## Happy Path: Request Lifecycle

### 1. Creation (`pending`)
- Client calls `POST /api/requests` specifying a provider, scheduled time, duration, location, and amount.
- `Requests::CreateService` creates the `Request` (state: `pending`) and immediately creates an associated `Payment` record (status: `pending`).
- Provider receives a `:request_created` notification.

### 2. Payment Hold (async, before the session)
- `PaymentHoldJob` runs periodically, finds `pending`/`confirmed` requests scheduled within the next 24 hours.
- Calls `PaymentGateway.hold(payment)` — reserves funds on the client's card without charging.
- Payment status transitions to `held`.

### 3. Confirmation (`confirmed`)
- Provider calls `PUT /api/requests/:id/confirm`.
- `Requests::ConfirmService` calls `request.confirm!` (state: `pending → confirmed`).
- Client receives a `:request_confirmed` notification.

### 4. Start (`in_progress`)
- Provider calls `PUT /api/requests/:id/start` when the session begins.
- `Requests::StartService` calls `request.start!` (state: `confirmed → in_progress`), recording `started_at`.
- Client receives a `:request_started` notification.

### 5. Completion (`completed`)
- Provider calls `PUT /api/requests/:id/complete` when done.
- `Requests::CompleteService` calls `request.complete!` (state: `in_progress → completed`), recording `completed_at`.
- If payment is `held`, `PaymentGateway.charge` captures the funds.
- Both client and provider receive `:request_completed` notifications.

### 6. Reviews (post-completion)
- `ReviewReminderJob` runs periodically, finds requests completed 24–48 hours ago.
- Sends `:review_reminder` to any party (client or provider) who hasn't left a review yet.
- Either party can submit a review via `POST /api/reviews`.

---

**State flow summary:**

```
pending → confirmed → in_progress → completed
```
