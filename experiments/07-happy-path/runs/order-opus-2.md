# Experiment: 07-happy-path
# App: order | Model: opus | Run: 2

---

The main entity is **Order**. Here's the happy path, step by step:

### 1. Client creates an Order → `pending`
- A **Client** picks a **Provider** and submits an order with a scheduled time, duration, location, and amount.
- `Orders::CreateService` saves the Order in `pending` state and creates a **Payment** (also `pending`) with a 10% platform fee.
- The Provider gets a `:order_created` notification.

### 2. Provider confirms → `confirmed`
- The Provider reviews the pending order and confirms it.
- State transitions from `pending` → `confirmed`.

### 3. Provider starts the session → `in_progress`
- At the scheduled time, the Provider marks the order as started.
- State transitions from `confirmed` → `in_progress`.
- `started_at` timestamp is recorded.

### 4. Provider completes the session → `completed`
- When the service is done, the Provider completes the order.
- State transitions from `in_progress` → `completed`.
- `completed_at` timestamp is recorded.
- If the payment was previously held, `PaymentGateway.charge` captures the funds.
- Both Client and Provider receive `:order_completed` notifications.

### 5. Reviews are submitted
- After completion, either the **Client** or **Provider** (or both) can leave a **Review** with a 1–5 rating.
- The `order_must_be_completed` validation enforces that reviews can only be left on completed orders.

---

**State diagram:** `pending` → `confirmed` → `in_progress` → `completed` → (reviewable)

The two unhappy exits are **cancel** (by Client, from `pending`/`confirmed`) and **reject** (by Provider, from `confirmed`/`in_progress`), both requiring a reason.
