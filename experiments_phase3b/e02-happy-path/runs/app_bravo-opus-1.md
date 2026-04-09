# Experiment: e02-happy-path
# App: app_bravo | Model: opus | Run: 1

---

Here's the happy path, step by step. The system has a two-phase lifecycle: **Request** then **Order**.

---

### Phase 1: Request (matching client with provider)

1. **Client creates a Request** — specifies `scheduled_at`, `duration_minutes`, and picks a `provider`. The request starts in **`pending`** state.

2. **Provider accepts the Request** — transitions to **`accepted`**, records `accepted_at`. (Alternatively the provider could decline, or the request could expire — but on the happy path, it's accepted.)

### Phase 2: Order (fulfillment and payment)

3. **Order is created** — linked to the accepted Request. It starts in **`pending`** state with `scheduled_at`, `duration_minutes`, `amount_cents`, and `currency` set. A **Payment** record is also created (status: `pending`).

4. **Order is confirmed** — transitions to **`confirmed`**.

5. **Payment is held** — the payment moves from `pending` to **`held`** (pre-authorization against the client's card), recording `held_at`.

6. **Order starts** — at the scheduled time, the order transitions to **`in_progress`**, recording `started_at`.

7. **Order completes** — after the service is delivered, transitions to **`completed`**, recording `completed_at`.

8. **Payment is charged** — the held payment is captured: status moves to **`charged`**, recording `charged_at`.

### Phase 3: Reviews

9. **Both parties leave reviews** — the client and provider each create a **Review** on the completed order (rating 1-5, optional body). The system enforces that only completed orders can be reviewed, and each party can review only once.

---

**Summary flow:**

```
Request(pending) → accept → Request(accepted)
    ↓
Order(pending) → confirm → Order(confirmed) → start → Order(in_progress) → complete → Order(completed)
    ↓                           ↓                                                          ↓
Payment(pending)          Payment(held)                                              Payment(charged)
                                                                                           ↓
                                                                                    Reviews by both parties
```
