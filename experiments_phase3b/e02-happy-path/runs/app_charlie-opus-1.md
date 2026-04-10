# Experiment: e02-happy-path
# App: app_charlie | Model: opus | Run: 1

---

Here's the happy path for a **Request** — the main entity in this system — step by step:

---

### 1. Client creates a Request (`pending`)

A client submits a request to a specific provider, specifying `scheduled_at`, `duration_minutes`, `amount_cents`, `currency`, `location`, and optional `notes`. The request is saved in `pending` state. The provider receives a `:request_created` notification.

**State:** `pending`

### 2. Provider accepts the Request (`accepted`)

The assigned provider reviews the pending request and accepts it. This:
- Transitions the request to `accepted` and sets `accepted_at`
- Creates a **Payment** record (with a 10% platform fee calculated from `amount_cents`)
- If the client has a default card on file, a **hold** is placed on their card via `PaymentGateway` (payment moves to `held` status)
- The client receives a `:request_accepted` notification

**State:** `accepted` | **Payment:** `held`

### 3. Provider starts the Request (`in_progress`)

When the scheduled time arrives, the provider marks the request as started. This sets `started_at` and notifies the client with `:request_started`.

**State:** `in_progress`

### 4. Provider completes the Request (`completed`)

Once the work is done, the provider completes the request. This:
- Sets `completed_at`
- If the payment was held, `PaymentGateway.charge` converts it to a **charge** (payment moves to `charged` status)
- Both client and provider receive `:request_completed` notifications

**State:** `completed` | **Payment:** `charged`

### 5. Both parties leave Reviews

After completion, both the client and provider can submit a review (rating 1-5 plus optional body text). Each party can review a request exactly once, and only completed requests can be reviewed.

---

### State machine summary (happy path)

```
pending → accepted → in_progress → completed
```

### Payment lifecycle (happy path)

```
pending → held (on accept) → charged (on complete)
```
