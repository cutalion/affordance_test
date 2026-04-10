# Experiment: e02-happy-path
# App: app_alpha | Model: opus | Run: 3

---

The main entity in this system is the **Request** — a service booking between a Client and a Provider. Here's the happy path step by step:

---

### 1. Client registers
`POST /api/clients/register` — A client signs up with their name and email. The system generates a unique `api_token` they'll use for all future API calls.

### 2. Provider registers
`POST /api/providers/register` — A provider signs up similarly, receiving their own `api_token`.

### 3. Client adds a payment card
`POST /api/cards` — The client stores a payment card (brand, last four digits, expiration, tokenized reference) and can mark one as their default via `PATCH /api/cards/:id/default`.

### 4. Client creates a Request
`POST /api/requests` — The client specifies a `provider_id`, `scheduled_at`, `duration_minutes`, and optionally `location` and `notes`. The `Requests::CreateService`:
- Builds the Request record in its initial **pending** state
- Saves it to the database
- Sends a notification to the provider (`:request_created` via push/SMS/email per their preferences)
- Returns the created request

### 5. Provider accepts the Request
`PATCH /api/requests/:id/accept` — The assigned provider reviews the pending request and accepts it. The `Requests::AcceptService`:
- Verifies the provider owns this request
- Transitions the state from **pending** → **accepted** (via AASM)
- Records `accepted_at` timestamp
- Sends a notification to the client (`:request_accepted`)

### 6. Service is delivered
At the `scheduled_at` time, the provider delivers the service for the specified `duration_minutes` at the given `location`. (There's no explicit "completed" state in the current model — accepted is the terminal happy-path state.)

---

**State machine summary:**

```
pending  ──accept──▶  accepted   ← happy path
   │
   ├──decline──▶  declined  (provider gives a reason)
   └──expire───▶  expired   (request goes stale)
```

The happy path is: **register → add card → create request → provider accepts → service happens**.
