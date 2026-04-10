# Experiment: e02-happy-path
# App: app_alpha | Model: opus | Run: 2

---

The main entity in this system is the **Request** — a service appointment that a client books with a provider. Here's the happy path, step by step:

---

### Step 1: Client registers
A client registers via `POST /api/clients/register`, providing their name, email, and phone. They receive an `api_token` for authenticating future API calls.

### Step 2: Provider registers
A provider registers via `POST /api/providers/register`, providing name, email, phone, and specialization. They also receive an `api_token`.

### Step 3: Client adds a payment card
The client calls `POST /api/cards` with card details (brand, last four digits, token, expiration). They can mark one card as the default via `PATCH /api/cards/:id/default`.

### Step 4: Client creates a Request
The client calls `POST /api/requests` with:
- `provider_id` — which provider they want
- `scheduled_at` — when the appointment should happen
- `duration_minutes` — how long it should last
- `location` and `notes` (optional)

Under the hood, `Requests::CreateService` builds the `Request` record (state starts as **pending**), saves it, and sends a notification to the provider (`NotificationService.notify` → push/SMS/email based on the provider's preferences).

### Step 5: Provider accepts the Request
The provider calls `PATCH /api/requests/:id/accept`. The `Requests::AcceptService`:
1. Verifies the request belongs to this provider
2. Transitions the state from **pending** → **accepted** (via AASM)
3. Sets `accepted_at` to the current time
4. Notifies the client that their request was accepted (push/SMS/email)

### Step 6: The appointment takes place
The request stays in the **accepted** state. The client and provider meet at the scheduled time and location.

---

### State machine summary

```
pending ──accept──▶ accepted   ✅ (happy path)
pending ──decline──▶ declined  (provider declines, must give reason)
pending ──expire───▶ expired   (no response in time)
```

The happy path is: **pending → accepted**. The two alternative terminal states (declined, expired) are the unhappy paths.
