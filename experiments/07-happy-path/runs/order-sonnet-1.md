# Experiment: 07-happy-path
# App: order | Model: sonnet | Run: 1

---

Here's the happy path for an **Order**:

---

**1. Client creates an order** (`Orders::CreateService`)
- Client submits `scheduled_at`, `duration_minutes`, `location`, `amount_cents`, etc.
- An `Order` is created in **`pending`** state.
- A `Payment` record (status: `"pending"`) is created simultaneously in a transaction.
- Provider is notified: `:order_created`.

**2. Payment is held** (`PaymentHoldJob`)
- A background job runs periodically and holds funds on the client's card for orders scheduled within the next 24 hours.
- `PaymentGateway.hold(payment)` is called; payment status becomes `"held"`.

**3. Provider confirms** (`Orders::ConfirmService`)
- Provider confirms the order → state: **`confirmed`**.
- Client is notified: `:order_confirmed`.

**4. Provider starts the order** (`Orders::StartService`)
- Provider marks the order as started → state: **`in_progress`**.
- `started_at` timestamp is recorded.
- Client is notified: `:order_started`.

**5. Provider completes the order** (`Orders::CompleteService`)
- Provider marks the order as done → state: **`completed`**.
- `completed_at` timestamp is recorded.
- If payment is in `"held"` state, `PaymentGateway.charge(payment)` is called to capture the funds.
- Both client and provider are notified: `:order_completed`.

**6. Reviews are requested** (`ReviewReminderJob`)
- 24–48 hours after completion, a job reminds both client and provider to leave a review if they haven't yet.

---

In summary: `pending` → `confirmed` → `in_progress` → `completed`, with payment hold happening before confirmation and payment capture on completion.
