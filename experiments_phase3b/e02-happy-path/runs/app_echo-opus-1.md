# Experiment: e02-happy-path
# App: app_echo | Model: opus | Run: 1

---

Here's the happy path for a **Request** — the main entity in this system — step by step:

---

### 1. Client creates a Request (`pending`)
A **Client** sends a request to a specific **Provider**, specifying `scheduled_at`, `duration_minutes`, `amount_cents`, `location`, and optional `notes`. The request is saved in `pending` state. The provider receives a `:request_created` notification.

### 2. Provider accepts the Request (`pending` → `accepted`)
The provider reviews the request and accepts it. On acceptance:
- The state transitions to `accepted`, and `accepted_at` is timestamped.
- A **Payment** record is created (`status: "pending"`) with the request amount plus a 10% platform fee.
- If the client has a default **Card** on file, `PaymentGateway.hold` is called — the payment is linked to that card and its status moves to `"held"` (funds are held, not yet charged).
- The client is notified (`:request_accepted`).

### 3. Provider starts the work (`accepted` → `in_progress`)
When the scheduled time arrives, the provider marks the request as started. The state moves to `in_progress`, `started_at` is timestamped, and the client is notified (`:request_started`).

### 4. Provider completes the work (`in_progress` → `completed`)
The provider marks the request as done. On completion:
- State transitions to `completed`, `completed_at` is timestamped.
- If the payment was previously held (`status: "held"`), `PaymentGateway.charge` finalizes the charge — the payment status moves to `"charged"`.
- Both client and provider are notified (`:request_completed`).

### 5. Both parties leave Reviews
After completion, both the **Client** and the **Provider** can create a **Review** on the request (rating 1–5, optional body text). The `request_must_be_completed` validation ensures reviews can only be left on completed requests. Each party can review only once (uniqueness on `request_id + author_type + author_id`).

---

**State flow summary:** `pending` → `accepted` → `in_progress` → `completed`

**Payment flow summary:** `pending` → `held` (at accept) → `charged` (at complete)
