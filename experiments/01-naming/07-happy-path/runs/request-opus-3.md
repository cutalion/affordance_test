# Experiment: 07-happy-path
# App: request | Model: opus | Run: 3

---

The main entity is **Request** — a service booking between a Client and a Provider. Here's the happy path:

### 1. `created` (initial state)
A client creates a request for a provider's service, specifying:
- `scheduled_at` — when the service should happen
- `duration_minutes` — how long it lasts
- `amount_cents` / `currency` — the price

A **Payment** record is created alongside it in `pending` status.

### 2. `accepted`
The provider reviews the incoming request and accepts it (`accept!`). The request moves from `created` → `accepted`.

### 3. Payment hold
As the scheduled time approaches (within 24 hours), the pending payment is placed on hold against the client's card (`payment.hold!` → status becomes `held`).

### 4. `started`
When the service begins, the request transitions `accepted` → `started`, and `started_at` is recorded.

### 5. `fulfilled`
When the service is completed, the request transitions `started` → `fulfilled`, and `completed_at` is recorded. The held payment is then charged (`payment.charge!` → status becomes `charged`).

### 6. Reviews
After fulfillment, both the client and provider can leave reviews (rating 1-5 with optional body). The review validation enforces that the request must be `fulfilled` before anyone can review it.

---

**Summary:** `created` → `accepted` → `started` → `fulfilled`, with payment going `pending` → `held` → `charged`, and reviews left afterward.
