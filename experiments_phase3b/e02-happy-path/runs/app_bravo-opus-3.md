# Experiment: e02-happy-path
# App: app_bravo | Model: opus | Run: 3

---

Here's the happy path, step by step:

## Happy Path: Request → Order → Payment → Review

**1. Client creates a Request** (state: `pending`)
- A Client asks a Provider for a service at a specific time (`scheduled_at`) for a given duration (`duration_minutes`).

**2. Provider accepts the Request** (state: `pending` → `accepted`)
- The provider calls `request.accept!`, which transitions the state and stamps `accepted_at`.

**3. An Order is created** (state: `pending`)
- An Order is built from the accepted Request (`order.request_id` links back). It captures the financial details: `amount_cents`, `currency`, plus the same `scheduled_at` and `duration_minutes`.

**4. Order is confirmed** (state: `pending` → `confirmed`)
- A Payment record is created (`status: "pending"`). The day before the scheduled time, the payment hold is placed (`payment.hold!` → `status: "held"`).

**5. Order starts** (state: `confirmed` → `in_progress`)
- When the service begins, `order.start!` is called, stamping `started_at`.

**6. Order completes** (state: `in_progress` → `completed`)
- When the service finishes, `order.complete!` is called, stamping `completed_at`. The payment is then charged (`payment.charge!` → `status: "charged"`).

**7. Reviews are left**
- Both the Client and Provider can each leave one Review on the completed Order (rating 1–5, optional body). The `order_must_be_completed` validation enforces that reviews only happen after completion.

---

**Key alternate flows:** Request can be `declined` or `expired` instead of accepted. Orders can be `canceled` (from pending/confirmed) or `rejected` (from confirmed/in_progress), with a corresponding `payment.refund!`.
