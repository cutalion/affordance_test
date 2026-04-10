# Experiment: e02-happy-path
# App: app_alpha | Model: opus | Run: 1

---

The main entity in this system is the **Request** — a service booking between a Client and a Provider. Here's the happy path step by step:

---

### 1. Client registers
`POST /api/clients/register` — A client signs up with their name and email. The system generates a unique `api_token` they'll use for all future API calls.

### 2. Provider registers
`POST /api/providers/register` — A provider signs up similarly, receiving their own `api_token`.

### 3. Client adds a payment card
`POST /api/cards` — The client stores a payment card (brand, last four, expiry, token). They can mark one as their default via `PATCH /api/cards/:id/default`.

### 4. Client creates a Request
`POST /api/requests` — The client specifies:
- `provider_id` — which provider they want
- `scheduled_at` — when the service should happen
- `duration_minutes` — how long
- `location` and `notes` (optional)

The `Requests::CreateService` saves the request in **pending** state and sends a notification to the provider (push/sms/email based on their preferences) with event `:request_created`.

### 5. Provider accepts the Request
`PATCH /api/requests/:id/accept` — The provider reviews the pending request and accepts it. The `Requests::AcceptService`:
- Verifies the provider owns this request
- Transitions the state from **pending** → **accepted** (via AASM)
- Sets `accepted_at` to the current time
- Notifies the client with event `:request_accepted`

### 6. Service happens
At the `scheduled_at` time, the provider delivers the service for `duration_minutes` at the specified `location`. (No in-app state change for this — the request stays in `accepted` state.)

---

**Alternate paths (non-happy):**
- **Decline**: Provider calls `PATCH /api/requests/:id/decline` with a `reason` → state goes to **declined**, client gets notified
- **Expire**: If nobody acts on a pending request, it can transition to **expired** (the `expire` event exists on the model, though no automated expiration job is wired up yet)
