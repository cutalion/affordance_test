# Experiment: e02-happy-path
# App: app_charlie | Model: opus | Run: 3

---

The main entity is **Request**. Here's the happy path:

### 1. **Pending** (initial state)
A **Client** creates a Request for a **Provider**, specifying:
- `scheduled_at` — when the service should happen
- `duration_minutes` — how long it lasts
- `amount_cents` / `currency` — the price

A **Payment** is created alongside it in `pending` status.

### 2. **Accepted**
The Provider reviews the request and calls `accept!`. This records `accepted_at`. The payment is placed on hold (`held` status via `payment.hold!`).

### 3. **In Progress**
When the scheduled time arrives, the request is started via `start!`. This records `started_at`.

### 4. **Completed**
After the service is delivered, `complete!` is called. This records `completed_at`. The held payment is charged (`payment.charge!`).

### 5. **Reviews**
Once the request is completed, both the **Client** and the **Provider** can leave a **Review** (rating 1–5, with optional body text). Each party can review only once per request, enforced by the uniqueness constraint on `[request_id, author_type, author_id]`.

---

**Summary:** `pending → accepted → in_progress → completed → reviewed`

The unhappy paths branch off at various points: a pending request can be **declined** (by provider), **expired** (by system), or **canceled** (by client); an accepted/in-progress request can be **rejected** or **canceled**, with the payment refunded.
