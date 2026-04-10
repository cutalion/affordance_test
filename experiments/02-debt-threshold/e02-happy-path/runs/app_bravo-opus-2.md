# Experiment: e02-happy-path
# App: app_bravo | Model: opus | Run: 2

---

The main entity in this system is the **Order**. Here's the happy path, step by step:

---

### 1. Client registers and adds a payment card
- A **Client** registers via `POST /api/clients/register` and receives an API token.
- The client adds a **Card** via `POST /api/cards` and marks it as default (`PATCH /api/cards/:id/default`).

### 2. Client creates a Request
- The client sends `POST /api/requests` with a provider, scheduled time, duration, location, and notes.
- `Requests::CreateService` saves the Request in **pending** state.
- The **Provider** is notified (`request_created`).

### 3. Provider accepts the Request
- The provider calls `PATCH /api/requests/:id/accept`.
- `Requests::AcceptService` transitions the Request from **pending** → **accepted** (sets `accepted_at`).
- Inside the same transaction, it automatically creates an **Order** (via `Orders::CreateService`) with `amount_cents: 350_000` (3,500 RUB) and a linked **Payment** record (status: `pending`, with a 10% fee calculated).
- The client is notified (`request_accepted`).
- The provider is notified (`order_created`).

### 4. Provider confirms the Order
- The provider calls `PATCH /api/orders/:id/confirm`.
- `Orders::ConfirmService` transitions the Order from **pending** → **confirmed**.
- The client is notified (`order_confirmed`).

### 5. Provider starts the Order
- The provider calls `PATCH /api/orders/:id/start`.
- `Orders::StartService` transitions the Order from **confirmed** → **in_progress** (sets `started_at`).
- The client is notified (`order_started`).

### 6. Provider completes the Order
- The provider calls `PATCH /api/orders/:id/complete`.
- `Orders::CompleteService` transitions the Order from **in_progress** → **completed** (sets `completed_at`).
- If the payment was in **held** status, `PaymentGateway.charge` is called, moving it to **charged** (sets `charged_at`).
- Both client and provider are notified (`order_completed`).

### 7. Review
- Either party can leave a **Review** on the completed order via `POST /api/orders/:id/reviews` with a rating and body. Each author can leave only one review per order (enforced by a unique index on `[order_id, author_type, author_id]`).

---

**State summary:**
- **Request:** `pending` → `accepted`
- **Order:** `pending` → `confirmed` → `in_progress` → `completed`
- **Payment:** `pending` → `held` → `charged`
