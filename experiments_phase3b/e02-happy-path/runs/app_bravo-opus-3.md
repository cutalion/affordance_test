# Experiment: e02-happy-path
# App: app_bravo | Model: opus | Run: 3

---

The main entity in this system is the **Request**, which flows through a lifecycle from a client booking a service provider, through to order fulfillment, payment, and review. Here's the happy path:

## Happy Path: Request → Order → Payment → Review

### 1. Client & Provider Registration
- A **Client** registers via `POST /api/clients/register`, getting an `api_token` for authentication.
- A **Provider** registers via `POST /api/providers/register` with a specialization.

### 2. Client Adds a Payment Card
- Client calls `POST /api/cards` with card details (token, brand, last_four, expiration).
- The first card is automatically set as the default.

### 3. Client Creates a Request
- Client calls `POST /api/requests` with `provider_id`, `scheduled_at`, `duration_minutes`, `location`, and `notes`.
- `Requests::CreateService` saves the request in **pending** state and notifies the provider (push/sms/email based on their preferences).

### 4. Provider Accepts the Request
- Provider calls `PATCH /api/requests/:id/accept`.
- The AASM state machine transitions the request from **pending** → **accepted**, and `accepted_at` is timestamped.

### 5. Order Is Created
- Client calls `POST /api/orders` with the provider, schedule, and pricing (`amount_cents`, `currency`).
- An Order is created in **pending** state, optionally linked to the accepted request.

### 6. Provider Confirms the Order
- Provider calls `PATCH /api/orders/:id/confirm`.
- Order transitions from **pending** → **confirmed**.

### 7. Provider Starts the Service
- Provider calls `PATCH /api/orders/:id/start`.
- Order transitions from **confirmed** → **in_progress**, `started_at` is timestamped.

### 8. Provider Completes the Service
- Provider calls `PATCH /api/orders/:id/complete`.
- Order transitions from **in_progress** → **completed**, `completed_at` is timestamped.

### 9. Payment Is Processed
- A Payment record is associated with the order, moving through statuses: **pending** → **held** (funds held before service) → **charged** (after completion).

### 10. Both Parties Leave Reviews
- Client and provider each call `POST /api/orders/:id/reviews` with a `rating` (1-5) and optional comment.
- Reviews are only allowed on completed orders, and each party can review only once per order.

---

The state flow in summary:

```
Request:  pending → accepted
Order:    pending → confirmed → in_progress → completed
Payment:  pending → held → charged
```
