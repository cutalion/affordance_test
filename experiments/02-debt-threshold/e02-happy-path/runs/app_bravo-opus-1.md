# Experiment: e02-happy-path
# App: app_bravo | Model: opus | Run: 1

---

Here's the happy path for an **Order** — the main entity in this system — step by step:

---

### 1. Client and Provider register
- A **Client** registers via `POST /api/clients/register` and receives an `api_token`.
- A **Provider** registers via `POST /api/providers/register` and receives an `api_token`.

### 2. Client adds a payment card
- The client adds a card via `POST /api/cards` and marks it as default (`PATCH /api/cards/:id/default`). This is required later for payment holds.

### 3. Client creates a Request
- The client calls `POST /api/requests` with a `provider_id`, `scheduled_at`, `duration_minutes`, location, and notes.
- `Requests::CreateService` saves the Request in **pending** state and notifies the provider.

### 4. Provider accepts the Request
- The provider calls `PATCH /api/requests/:id/accept`.
- `Requests::AcceptService` transitions the Request from **pending** → **accepted** and automatically creates an **Order** (with a hardcoded amount of 350,000 copecks / 3,500 RUB) plus a **Payment** record in **pending** status. The client is notified.

### 5. Provider confirms the Order
- The provider calls `PATCH /api/orders/:id/confirm`.
- `Orders::ConfirmService` transitions the Order from **pending** → **confirmed** and notifies the client.

### 6. Provider starts the Order
- The provider calls `PATCH /api/orders/:id/start`.
- `Orders::StartService` transitions the Order from **confirmed** → **in_progress**, records `started_at`, and notifies the client.

### 7. Provider completes the Order
- The provider calls `PATCH /api/orders/:id/complete`.
- `Orders::CompleteService` transitions the Order from **in_progress** → **completed**, records `completed_at`.
- If the payment was previously held (status `"held"`), `PaymentGateway.charge` is called to finalize the charge against the client's default card.
- Both client and provider are notified.

### 8. Both parties leave Reviews
- Either party calls `POST /api/orders/:id/reviews` with a `rating` (1–5) and optional `body`.
- Reviews are only allowed on completed orders, and each author can review a given order only once.

---

**State machines summarized:**

- **Request:** `pending` → `accepted` (happy) / `declined` / `expired`
- **Order:** `pending` → `confirmed` → `in_progress` → `completed` (happy) / `canceled` / `rejected`
- **Payment:** `pending` → `held` → `charged` (happy) / `refunded`

The system is essentially a service marketplace where clients book providers, the provider confirms and fulfills the work, payment is captured on completion, and both sides review each other.
