# Experiment: 07-happy-path
# App: request_clean | Model: sonnet | Run: 3

---

Here's the happy path for a **Request** (the main entity):

---

## Happy Path: Request Lifecycle

### 1. Client creates a Request — `pending`
- Client submits `scheduled_at`, `duration_minutes`, `location`, `amount_cents`, etc.
- `Requests::CreateService` saves the Request (state: `pending`) and creates a linked `Payment` (status: `pending`).
- Provider is notified: `:request_created`.

### 2. Payment is held — `Payment: held`
- `PaymentHoldJob` runs periodically. For any `pending`/`confirmed` request scheduled within the next 24 hours, it calls `PaymentGateway.hold`.
- Hold charges the client's default card and marks the payment `held`.

### 3. Provider confirms — `confirmed`
- `Requests::ConfirmService` transitions the request `pending → confirmed`.
- Client is notified: `:request_confirmed`.

### 4. Provider starts — `in_progress`
- `Requests::StartService` transitions `confirmed → in_progress`, records `started_at`.
- Client is notified: `:request_started`.

### 5. Provider completes — `completed`
- `Requests::CompleteService` transitions `in_progress → completed`, records `completed_at`.
- Since payment is `held`, `PaymentGateway.charge` is called immediately — money is captured.
- Both client and provider are notified: `:request_completed`.

### 6. Reviews are requested
- 24–48 hours after `completed_at`, `ReviewReminderJob` sends `:review_reminder` to anyone who hasn't left a review yet (both client and provider).

---

**State machine summary:**

```
pending → confirmed → in_progress → completed
```

**Payment state:**
```
pending → held (before session) → charged (on completion)
```
