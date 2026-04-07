# Experiment: 07-happy-path
# App: request | Model: sonnet | Run: 3

---

Here's the happy path for a **Request** (the main entity):

---

## Happy Path: `created` → `accepted` → `started` → `fulfilled`

### 1. Client creates a Request (`created`)
- Client sends `POST /api/requests` with `provider_id`, `scheduled_at`, `duration_minutes`, `amount_cents`, etc.
- `Requests::CreateService` creates the Request (state: `created`) and a linked `Payment` (status: `pending`) in a transaction.
- Provider is notified.

### 2. Provider accepts (`accepted`)
- Provider sends `POST /api/requests/:id/accept`.
- `Requests::AcceptService` transitions state: `created` → `accepted`.
- Client is notified.

> At some point before the service starts, a background process holds the payment: `PaymentGateway.hold(payment)` moves Payment to `held` (charges the client's default card as an authorization hold). This is driven by `Payment.pending_holds` scope (requests within the next 24 hours).

### 3. Provider starts the service (`started`)
- Provider sends `POST /api/requests/:id/start`.
- `Requests::StartService` transitions: `accepted` → `started`, records `started_at`.
- Client is notified.

### 4. Provider fulfills the service (`fulfilled`)
- Provider sends `POST /api/requests/:id/fulfill`.
- `Requests::FulfillService` transitions: `started` → `fulfilled`, records `completed_at`.
- If Payment is `held`, `PaymentGateway.charge(payment)` is called — converts the hold into an actual charge.
- Both client and provider are notified.

---

### State diagram (happy path)

```
created → accepted → started → fulfilled
                                   ↓
                            payment charged
```

### Notable detail: `created_accepted`
There's an alternate creation path (`POST /api/requests/create_direct`) where a **provider** creates the request directly for a known client via `Requests::CreateAcceptedService`. This skips the `created` state entirely, producing `created_accepted` — which can still `start` and `fulfill` via the same happy path.
