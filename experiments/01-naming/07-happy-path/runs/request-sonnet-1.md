# Experiment: 07-happy-path
# App: request | Model: sonnet | Run: 1

---

Here's the happy path for a `Request`:

---

## Happy Path: `created` → `accepted` → `started` → `fulfilled`

### 1. Client creates a Request (`created`)
`Requests::CreateService` — client picks a provider, specifies time, duration, location, and amount.

- A `Request` is persisted in the `created` (initial) state.
- A `Payment` record is created with `status: "pending"` and a 10% platform fee calculated.
- The provider is notified.

### 2. Provider accepts the Request (`accepted`)
`Requests::AcceptService` — provider reviews and agrees to the booking.

- Transitions `created` → `accepted`.
- Client is notified.

### 3. Provider starts the session (`started`)
`Requests::StartService` — provider marks that the session has begun.

- Transitions `accepted` → `started`.
- `started_at` timestamp is recorded.
- Client is notified.

### 4. Provider fulfills the Request (`fulfilled`)
`Requests::FulfillService` — provider marks the session as complete.

- Transitions `started` → `fulfilled`.
- `completed_at` timestamp is recorded.
- If payment is in `"held"` status, `PaymentGateway.charge` is called to capture funds.
- Both client and provider are notified.

---

**Note:** There's also a `created_accepted` state (with a `CreateAcceptedService`) — a legacy artifact from Kidsout's invitation era where an accept could happen at creation time. The happy path skips it; it's a shortcut that merges steps 1+2 and also transitions to `started` normally.
