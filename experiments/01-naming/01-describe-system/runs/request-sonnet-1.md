# Experiment: 01-describe-system
# App: request | Model: sonnet | Run: 1

---

Here is a thorough description of what this system does:

---

## Domain

This is a **service booking marketplace** — a Ruby on Rails JSON API backend that connects **clients** (people who need a service) with **providers** (people who deliver a service). Think of it as a platform like a home-services marketplace or a freelance booking app, where a client schedules a session with a provider, pays for it, and both parties can review each other afterward.

---

## Main Entities

| Entity | Description |
|---|---|
| **Client** | A consumer who books services. Has an email, phone, API token for auth, notification preferences, and a set of saved payment cards. |
| **Provider** | A service professional. Has a specialization, a numeric rating (0–5), an active flag, and their own API token and notification preferences. |
| **Request** | The core entity — a scheduled service session between a specific client and provider. Holds the time, duration, location, agreed price (in cents + currency), and a rich lifecycle state. |
| **Payment** | One-to-one with a Request. Tracks payment lifecycle: `pending → held → charged` (or `refunded`). Stores the amount, fee (10%), currency, and the card used. |
| **Card** | A saved payment card belonging to a client (brand, last four digits, expiry, token). One card can be marked as the default. |
| **Review** | A post-service rating (1–5) + optional text. Polymorphic author (either a Client or a Provider). Both parties can review the same request, but only after it is `fulfilled`. |

---

## Request Lifecycle (State Machine)

The `Request` model uses **AASM** to enforce a strict state machine:

```
                        ┌──────────────────────────────────────────────┐
                        │                                              ↓
[created] ──accept──→ [accepted] ──start──→ [started] ──fulfill──→ [fulfilled]
    │          │           │                    │
    │          │           └──reject──────────→ [rejected]
    │          │
    │          └──cancel──→ [canceled]  (also possible from created_accepted)
    │
    ├──decline──→ [declined]
    ├──miss─────→ [missed]
    └──cancel──→ [canceled]

[created_accepted] (provider-initiated, already accepted) ──start──→ [started] ...
```

Key rules:
- **Cancel** (by client) and **Reject** (by provider mid-service) both trigger a payment **refund** if the payment was already held or charged.
- **Fulfill** triggers a payment **charge** if the payment was held.
- A `cancel_reason` / `reject_reason` is required when entering those states.

---

## Typical Workflow

### Standard booking (client-initiated)
1. **Client creates a request** — picks a provider, sets `scheduled_at`, duration, location, notes, and agreed price. A `Payment` record (`pending`) is created automatically.
2. **Provider accepts or declines** — accept moves state to `accepted`; decline ends the flow.
3. **Payment hold** — a background job (`PaymentHoldJob`) runs periodically and holds funds on the client's default card for requests scheduled within the next 24 hours (`pending → held`).
4. **Provider starts the request** — state moves to `started`, `started_at` is timestamped.
5. **Provider fulfills the request** — state moves to `fulfilled`, `completed_at` is timestamped, and the held payment is **charged**.
6. **Both parties leave reviews** — a background job (`ReviewReminderJob`) sends reminders 24–48 hours after completion if a review hasn't been left. The client's review updates the provider's rating.

### Direct booking (provider-initiated)
A provider can create a `created_accepted` request on behalf of a client (skipping the accept/decline step). The rest of the flow is identical from step 3 onward.

### Cancellation / Rejection
- **Client cancels** (from `created`, `accepted`, or `created_accepted`) — requires a reason; payment is refunded if held/charged; provider is notified.
- **Provider rejects** (from `accepted`, `created_accepted`, or `started`) — requires a reason; payment is refunded; client is notified.

---

## Supporting Infrastructure

- **Authentication**: Token-based (Bearer), shared by both Clients and Providers via their `api_token`.
- **Notifications**: `NotificationService` dispatches push, SMS, and email (via mailer) based on each recipient's preferences, triggered at every state transition.
- **Background Jobs**: Solid Queue-backed jobs for automatic payment holds and review reminders.
- **Admin**: There is an `admin` namespace in controllers (not yet explored in detail), suggesting an internal management interface alongside the API.
