# Experiment: e02-happy-path
# App: app_delta | Model: opus | Run: 1

---

The main entity in this system is the **Order**. Here's the happy path, step by step:

---

### 1. Client creates a Request (pending)
A **Client** sends a service request to a specific **Provider**, specifying a scheduled time, duration, location, and notes. The Request is created in `pending` state. The Provider receives a notification.

### 2. Provider accepts the Request (pending → accepted)
The Provider reviews the Request and accepts it. This automatically:
- Transitions the Request to `accepted` state
- Creates an **Order** (in `pending` state) with the same details plus a price (amount_cents: 350,000 RUB)
- Creates a **Payment** record (`pending` status) linked to the Order, including a 10% platform fee
- Notifies the Client that their request was accepted

### 3. Provider confirms the Order (pending → confirmed)
The Provider confirms the Order, moving it to `confirmed` state. The Client is notified.

### 4. Provider starts the Order (confirmed → in_progress)
When the scheduled time arrives, the Provider marks the Order as started. The `started_at` timestamp is recorded. The Client is notified.

### 5. Provider completes the Order (in_progress → completed)
After the service is delivered, the Provider marks the Order as completed. The `completed_at` timestamp is recorded. If the Payment was in `held` status, it gets charged via the PaymentGateway. Both Client and Provider are notified.

### 6. Review
After completion, either the Client or Provider (or both) can leave a **Review** with a rating (1-5). The order must be in `completed` state for reviews to be allowed. Each party can only review once per order.

---

**Payment lifecycle in parallel:** `pending` → `held` (funds pre-authorized) → `charged` (on order completion). It can also be `refunded` if needed.

**State summary:**
- Request: `pending` → `accepted`
- Order: `pending` → `confirmed` → `in_progress` → `completed`
- Payment: `pending` → `held` → `charged`
