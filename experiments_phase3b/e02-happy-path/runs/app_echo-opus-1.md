# Experiment: e02-happy-path
# App: app_echo | Model: opus | Run: 1

---

The main entity is **Request**. Here's the happy path, step by step:

### 1. **Client creates a Request** → state: `pending`
A client submits a request to a provider, specifying `scheduled_at`, `duration_minutes`, `amount_cents`, and `currency`. Optionally linked to an announcement. A **Payment** is created in `pending` status.

### 2. **Provider accepts** → state: `accepted`
The provider reviews the pending request and calls `accept!`. Timestamps `accepted_at`. The payment is put on **hold** (`held` status) — funds are reserved on the client's card.

### 3. **Service begins** → state: `in_progress`
At the scheduled time, `start!` is called. Timestamps `started_at`.

### 4. **Service completes** → state: `completed`
When the session ends, `complete!` is called. Timestamps `completed_at`. The held payment is **charged** (`charged` status) — funds transfer to the provider.

### 5. **Both parties leave Reviews**
Now that the request is completed, the client and provider can each submit a **Review** (rating 1–5, one per author per request). The `request_must_be_completed` validation enforces this ordering.

---

**Unhappy paths branch off at steps 1–3:**
- **Declined** — provider declines a pending request (requires `decline_reason`)
- **Expired** — pending request times out without a response
- **Canceled** — client cancels while still pending or accepted (requires `cancel_reason`)
- **Rejected** — provider rejects after accepting or during progress (requires `reject_reason`); payment would be refunded
