# Experiment: e02-happy-path
# App: app_charlie | Model: opus | Run: 2

---

The main entity in this system is the **Request** — a service booking between a Client and a Provider. Here's the happy path, step by step:

---

### 1. Client creates a Request (`pending`)

A client submits a request for a provider's services via `Requests::CreateService`. The request is created with a scheduled time, duration, location, notes, and price (`amount_cents` / `currency`). It starts in the **pending** state. The provider receives a `:request_created` notification.

### 2. Provider accepts the Request (`pending` → `accepted`)

The assigned provider reviews and accepts via `Requests::AcceptService`. This:
- Transitions the request to **accepted** and records `accepted_at`
- Creates a **Payment** record (with a 10% platform fee calculated from the amount)
- If the client has a default card on file, a **hold** is placed on the card via `PaymentGateway.hold` — the payment moves from `pending` → `held`
- The client is notified (`:request_accepted`)

### 3. Provider starts the work (`accepted` → `in_progress`)

When the scheduled time arrives, the provider signals they've begun via `Requests::StartService`. The request transitions to **in_progress** and records `started_at`. The client is notified (`:request_started`).

### 4. Provider completes the work (`in_progress` → `completed`)

The provider marks the request done via `Requests::CompleteService`. This:
- Transitions the request to **completed** and records `completed_at`
- If the payment was previously held, it is now **charged** via `PaymentGateway.charge` (`held` → `charged`)
- Both client and provider are notified (`:request_completed`)

### 5. Both parties leave Reviews

After completion, both the client and provider can submit a `Review` (rating 1-5, optional body text). The system enforces that reviews can only be left on completed requests, and each party can only review once per request.

---

**State machine summary for the happy path:**

```
Request:  pending → accepted → in_progress → completed
Payment:  pending → held → charged
```
