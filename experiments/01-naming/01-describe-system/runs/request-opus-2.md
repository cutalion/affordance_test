# Experiment: 01-describe-system
# App: request | Model: opus | Run: 2

---

Now I have a clear picture. Here's a description of the system:

---

## Domain

This is a **service marketplace / on-demand booking platform** — think of something like a cleaning service, tutoring, or home repair marketplace where **clients** book time-based services from **providers** (specialists).

## Main Entities

1. **Client** — A customer who books services. Has an email, name, phone, API token for authentication, and notification preferences. Can have multiple payment cards.

2. **Provider** — A service professional/specialist. Has a rating, specialization, active/inactive status, and notification preferences. Accepts or declines requests from clients.

3. **Request** (the central entity) — A booking/appointment for a service. Contains: which client wants it, which provider will perform it, when it's scheduled (`scheduled_at`), how long it lasts (`duration_minutes`), where (`location`), how much it costs (`amount_cents` in RUB), and optional notes. Has a complex state machine (see workflow below).

4. **Payment** — Tied 1:1 to a Request. Tracks the money flow through statuses: `pending → held → charged` (or `refunded`). Includes a 10% platform fee.

5. **Card** — A client's payment card (brand, last four digits, expiration, token). One card can be marked as default.

6. **Review** — Polymorphic: either the client or the provider can leave a review (with a 1–5 rating and text body) on a completed request. One review per author per request.

## Typical Workflow

1. **Client creates a Request** — picks a provider, time slot, duration, and price. A `Payment` record is automatically created in `pending` status. The provider is notified. The request starts in **`created`** state.

2. **Provider responds**:
   - **Accepts** → moves to **`accepted`** (provider agrees to do the job)
   - **Declines** → moves to **`declined`** (provider explicitly refuses)
   - If the provider doesn't respond in time → **`missed`**

3. **Alternative: Direct/pre-accepted creation** — A provider can create a request via `POST /api/requests/direct` using `CreateAcceptedService`, which starts in the **`created_accepted`** state (skipping the acceptance step). The client is notified instead.

4. **Service execution** — The provider **starts** the request (→ **`started`**, timestamps `started_at`), then **fulfills** it when done (→ **`fulfilled`**, timestamps `completed_at`).

5. **Cancellation/Rejection** — A request can be **canceled** (by the client, from `created`/`accepted`/`created_accepted`, requires a reason) or **rejected** (from `accepted`/`created_accepted`/`started`, requires a reason).

6. **Payment lifecycle** — The payment is held before the scheduled time, charged upon fulfillment, or refunded upon cancellation/rejection.

7. **Reviews** — After fulfillment, both client and provider can leave reviews on the request.

## Architecture Notes

- **Rails 8.1 API-mode** app with a separate **admin HTML section** (basic auth, ERB views) for read-only oversight of requests, clients, providers, and payments.
- Uses **AASM** for state machine management on the Request model.
- Service objects (`Requests::CreateService`, `Requests::AcceptService`, etc.) encapsulate business logic for each state transition.
- This app is part of an **AI affordance experiment** — an identical sibling app (`affordance_order`) exists with the same structure but uses "Order" instead of "Request" with cleaner state names, to study how entity naming affects AI reasoning about the system.
