# Experiment: e02-happy-path
# App: app_echo | Model: opus | Run: 2

---

The main entity is **Request**. Here's the happy path, step by step:

### 1. **`pending`** — Client creates a Request
A client submits a request to a provider, specifying `scheduled_at`, `duration_minutes`, `amount_cents`, and `currency`. Optionally linked to an announcement. A **Payment** is created alongside it in `pending` status.

### 2. **`accepted`** — Provider accepts
The provider reviews and calls `request.accept!`. This transitions the state to `accepted` and records `accepted_at`. The payment can be put on hold (`payment.hold!` → status `held`).

### 3. **`in_progress`** — Service starts
When the scheduled time arrives, `request.start!` is called. State moves to `in_progress`, `started_at` is recorded.

### 4. **`completed`** — Service finishes
After the service is delivered, `request.complete!` is called. State moves to `completed`, `completed_at` is recorded. The held payment is charged (`payment.charge!` → status `charged`).

### 5. **Reviews** — Both sides leave feedback
Once completed, both the **client** and the **provider** can leave a `Review` (rating 1–5 + optional body). Each side can review only once per request. The `request_must_be_completed` validation enforces that reviews can't be left until the request reaches `completed`.

---

**Unhappy paths** branch off at the early stages: the provider can **decline** a pending request, it can **expire** if not acted on, either party can **cancel** (from pending/accepted), or the provider's work can be **rejected** (from accepted/in_progress) — each requiring a reason. A refunded payment (`payment.refund!`) would accompany cancellations or rejections.
