# Experiment: e02-happy-path
# App: app_charlie | Model: opus | Run: 2

---

The main entity is **Request** — a service booking between a Client and a Provider. Here's the happy path:

### 1. **Pending** (initial state)
A Client creates a Request for a Provider, specifying:
- `scheduled_at` — when the service should happen
- `duration_minutes` — how long it lasts
- `amount_cents` / `currency` — the agreed price

A **Payment** is created alongside it (status: `pending`), linked to one of the Client's saved Cards.

### 2. **Accepted**
The Provider reviews and **accepts** the request. `accepted_at` is recorded. At this point the payment is typically **held** (`payment.hold!`) — funds are reserved on the Client's card.

### 3. **In Progress**
When the scheduled time arrives, the request is **started**. `started_at` is recorded.

### 4. **Completed**
After the service is delivered, the request is **completed**. `completed_at` is recorded. The held payment is **charged** (`payment.charge!`).

### 5. **Reviewed**
Both the Client and Provider can leave a **Review** (rating 1–5, optional body). Reviews are only allowed after completion. Each party can review once per request.

---

**Unhappy paths** branch off at various points: the Provider can **decline** a pending request, it can **expire** if not acted on, the Client can **cancel** (while pending or accepted), or the Provider can **reject** (while accepted or in progress) — each requiring a reason. A charged payment can also be **refunded**.
