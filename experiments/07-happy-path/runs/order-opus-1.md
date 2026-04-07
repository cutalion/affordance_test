# Experiment: 07-happy-path
# App: order | Model: opus | Run: 1

---

The main entity is **Order**. Here's the happy path, step by step:

### 1. **Pending** (initial state)
A client creates an order for a provider with a scheduled time, duration, location, notes, and price (`amount_cents` in RUB). A **Payment** record is also created in `pending` status, linked to the client's card.

### 2. **Payment held**
Before the appointment (within 24 hours, per the `pending_holds` scope), the payment is held on the client's card — `payment.hold!` sets status to `held`.

### 3. **Confirmed**
The provider confirms the order (`order.confirm!`), transitioning it from `pending` → `confirmed`.

### 4. **In Progress**
At the scheduled time, the order is started (`order.start!`), moving it to `in_progress` and recording `started_at`.

### 5. **Completed**
The service is delivered and the order is completed (`order.complete!`), moving it to `completed` and recording `completed_at`.

### 6. **Payment charged**
After completion, the held payment is charged — `payment.charge!` sets status to `charged` with a timestamp.

### 7. **Reviews**
Both the client and provider can leave a review (rating 1–5 with optional text). Each party can review the order exactly once, and only after it's completed.

---

The unhappy paths branch off as **cancel** (from `pending` or `confirmed`, requires a `cancel_reason`, payment gets refunded) or **reject** (from `confirmed` or `in_progress`, requires a `reject_reason`).
