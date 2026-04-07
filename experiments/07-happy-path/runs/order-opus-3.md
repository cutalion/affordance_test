# Experiment: 07-happy-path
# App: order | Model: opus | Run: 3

---

The main entity is **Order**. Here's its happy path, step by step:

### 1. **Pending** (initial state)
A client creates an order for a provider. The order captures:
- `scheduled_at` — when the service happens
- `duration_minutes` — how long it lasts
- `amount_cents` / `currency` — the price (defaults to RUB)
- `location`, `notes` — optional details

A **Payment** record is created alongside it in `pending` status.

### 2. **Confirmed**
The provider confirms the order (`order.confirm!`). This transitions `pending → confirmed`.

Around this time (up to 1 day before `scheduled_at`, per the `pending_holds` scope), the payment is **held** against the client's card (`payment.hold!`), reserving the funds.

### 3. **In Progress**
When the scheduled time arrives, the order is started (`order.start!`). This transitions `confirmed → in_progress` and records `started_at`.

### 4. **Completed**
After the service is delivered, the order is completed (`order.complete!`). This transitions `in_progress → completed` and records `completed_at`.

The held payment is then **charged** (`payment.charge!`), capturing the funds.

### 5. **Reviewed**
Both the client and the provider can leave a **Review** (rating 1–5, optional body). Reviews are only allowed on completed orders, and each party can review only once.

---

**Alternate (unhappy) paths:**
- **Canceled** — client or provider cancels from `pending` or `confirmed` (requires a `cancel_reason`). Payment would be refunded if already held.
- **Rejected** — provider rejects from `confirmed` or `in_progress` (requires a `reject_reason`). Payment would be refunded.
