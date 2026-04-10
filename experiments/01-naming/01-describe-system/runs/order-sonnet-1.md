# Experiment: 01-describe-system
# App: order | Model: sonnet | Run: 1

---

Here is a comprehensive description of the system:

---

## Domain

This is a **service marketplace / on-demand booking platform** — a Ruby on Rails API backend that facilitates booking service appointments between **clients** (customers) and **providers** (service professionals). The currency defaults to RUB (Russian Rubles), suggesting a Russian-market context. Think of it like a booking layer for something like a beauty salon, cleaning service, or similar on-demand professional service.

---

## Main Entities

| Entity | Role |
|---|---|
| **Client** | The customer who books services. Has an API token for authentication, a set of saved payment cards, configurable notification preferences (push/SMS/email), and can leave reviews. |
| **Provider** | The service professional who fulfills bookings. Has a specialization, an active/inactive flag, a rating (0–5), and also has notification preferences. |
| **Order** | The central entity — a scheduled appointment linking a client to a provider. Carries scheduling details (`scheduled_at`, `duration_minutes`), location, notes, price (`amount_cents`), and a **state machine** (see below). |
| **Payment** | A 1-to-1 record per order tracking the financial transaction lifecycle: `pending → held → charged` (or `refunded`). Includes a platform fee (10% of order amount). |
| **Card** | A saved payment card belonging to a client (brand, last four digits, expiry, token). One card can be set as the default. |
| **Review** | A post-completion rating (1–5) with optional text, written by either the client or the provider about a completed order. Each party can leave exactly one review per order. |

---

## Order State Machine

Orders follow a strict lifecycle managed via the **AASM** gem:

```
pending → confirmed → in_progress → completed
   ↓           ↓            ↓
canceled    canceled      rejected
            rejected
```

- **pending** — created, awaiting provider confirmation
- **confirmed** — provider accepted; payment hold will be placed
- **in_progress** — service started (timestamps `started_at`)
- **completed** — service finished (timestamps `completed_at`); reviews can now be written
- **canceled** — client or provider backed out from pending/confirmed
- **rejected** — provider aborted a confirmed or in-progress order (requires a reason)

---

## Typical Workflow

1. **Booking**: A client POSTs to create an order for a specific provider with a scheduled time, duration, amount, and optional notes. A `Payment` record (status: `pending`, with a 10% platform fee) is created atomically in the same transaction. The provider is notified.

2. **Confirmation**: The provider confirms the order via their API endpoint. The client is notified. The order moves to `confirmed`.

3. **Payment Hold**: A background job (`PaymentHoldJob`) runs periodically and, for all pending/confirmed orders scheduled within the next 24 hours, places a hold on the client's default card via the `PaymentGateway`.

4. **Execution**: The provider starts the order (`in_progress`) and eventually completes it (`completed`). The payment is charged upon completion.

5. **Cancellation/Rejection**: Either party can cancel (with a reason), and a refund is issued for any held/charged payment.

6. **Reviews**: After completion, both client and provider receive a reminder notification (via `ReviewReminderJob`, sent 24–48 hours after `completed_at`) and can each submit a 1–5 star review.

---

## Supporting Infrastructure

- **API**: A token-authenticated JSON API (`Authorization: Bearer <token>`) with separate controllers for clients, providers, orders, payments, cards, and reviews. There is also an `admin` namespace.
- **Notifications**: A `NotificationService` delivers events via push, SMS, and email (through `OrderMailer`) based on per-user preferences, and logs all deliveries.
- **Background Jobs**: Solid Queue-backed async jobs handle payment holds and review reminders.
- **Services layer**: Each order lifecycle transition (`create`, `confirm`, `start`, `complete`, `cancel`, `reject`) is encapsulated in a dedicated `Orders::XxxService` class that handles authorization, state transitions, notifications, and payment operations.
