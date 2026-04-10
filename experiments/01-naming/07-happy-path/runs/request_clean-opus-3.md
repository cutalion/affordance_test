# Experiment: 07-happy-path
# App: request_clean | Model: opus | Run: 3

---

The main entity is **Request**. Here's the happy path, step by step:

### 1. **`pending`** — Client submits a request
A client creates a Request specifying a provider, scheduled time, duration, and amount. The request starts in the `pending` state. A Payment record is also created (status: `pending`) linked to the client's card.

### 2. **`confirmed`** — Provider accepts
The provider confirms the request (`request.confirm!`). This transitions the state from `pending` → `confirmed`. Around this time, the payment can be held (`payment.hold!`) to guarantee funds on the client's card.

### 3. **`in_progress`** — Service begins
When the scheduled time arrives, the request is started (`request.start!`), moving it from `confirmed` → `in_progress`. The `started_at` timestamp is recorded.

### 4. **`completed`** — Service finished
Once the service is done, the request is completed (`request.complete!`), transitioning from `in_progress` → `completed`. The `completed_at` timestamp is recorded. The held payment is then charged (`payment.charge!`).

### 5. **Reviews** — Both sides rate the experience
After completion, both the client and the provider can leave a Review (rating 1–5 with optional comment). The model enforces that only completed requests can be reviewed, and each party can only review once.

---

**Unhappy paths** branch off at steps 1–2: the client can **cancel** from `pending` or `confirmed`, and the provider can **reject** from `confirmed` or `in_progress` (both require a reason). A rejected/canceled payment would be refunded (`payment.refund!`).
