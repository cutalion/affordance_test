# Experiment: 07-happy-path
# App: request_clean | Model: opus | Run: 1

---

The main entity is **Request**. Here's the happy path, step by step:

### 1. **Client creates a Request** → state: `pending`
A client submits a request specifying a `provider`, `scheduled_at` time, `duration_minutes`, and `amount_cents`/`currency`. The request starts in the **pending** state.

### 2. **Provider confirms** → state: `confirmed`
The assigned provider reviews and confirms the request. Transitions: `pending → confirmed`.

### 3. **Service begins** → state: `in_progress`
At the scheduled time, the request is started. Transitions: `confirmed → in_progress`. The `started_at` timestamp is recorded.

### 4. **Service completes** → state: `completed`
The provider finishes the service. Transitions: `in_progress → completed`. The `completed_at` timestamp is recorded.

### 5. **Payment is charged**
The associated Payment moves through its own lifecycle alongside the request:
- **pending** — created with the request
- **held** — funds held on the client's card (likely around confirmation, for requests within the next 24h per the `pending_holds` scope)
- **charged** — captured after completion

### 6. **Reviews are left**
Once the request is `completed`, both the client and provider can leave a **Review** (rating 1–5 with optional body). Each party can review only once per request.

---

**Unhappy paths** branch off at steps 1–2: the client can **cancel** from `pending` or `confirmed`, and the provider can **reject** from `confirmed` or `in_progress` (both require a reason). A charged payment can be **refunded**.
