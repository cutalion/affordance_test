# Experiment: 01-describe-system
# App: order | Model: sonnet | Run: 2

---

Here is a comprehensive description of the system:

---

## Domain

This is a **service marketplace / on-demand booking platform** — specifically a Rails API application that connects **clients** (customers) with **providers** (service professionals). Based on the currency default (RUB) and the `specialization` field on providers, it appears to be a Russian-market platform for booking personal services (e.g., beauty, wellness, repair, tutoring, or similar).

---

## Main Entities

| Entity | Description |
|---|---|
| **Client** | The customer who books services. Has an API token for authentication, contact info, saved payment cards, and notification preferences (push/SMS/email). |
| **Provider** | The service professional who fulfills orders. Has a specialization, a rating (0–5), an active/inactive status, and their own notification preferences. |
| **Order** | The core booking record. Links a client to a provider for a scheduled appointment with a time, duration, location, and price. Drives the main workflow via a state machine. |
| **Payment** | One-to-one with an order. Tracks the financial transaction lifecycle (hold → charge → refund). Stores amount, fee (10%), and the card used. |
| **Card** | A saved payment card belonging to a client (tokenized, storing brand, last four digits, expiry). One card can be the client's default. |
| **Review** | A post-completion rating (1–5) with optional text. Both the client and the provider can leave a review for the same order (polymorphic author). |

---

## Order State Machine & Typical Workflow

The lifecycle of an order follows a clear state machine:

```
pending → confirmed → in_progress → completed
   ↓           ↓            ↓
canceled    canceled     rejected
            rejected
```

1. **Client creates an order** (`pending`) — specifies a provider, date/time, duration, location, and price. A `Payment` record is created immediately in `pending` status with a 10% platform fee calculated.

2. **Provider confirms the order** (`confirmed`) — the provider accepts the booking. The client is notified.

3. **Payment is held** — before the appointment, the `PaymentGateway` places a hold on the client's default card (funds are reserved but not yet charged).

4. **Provider starts the order** (`in_progress`) — marks the job as begun, recording `started_at`.

5. **Provider completes the order** (`completed`) — marks the job done, recording `completed_at`. The held payment is **charged** automatically. Both client and provider are notified.

6. **Both parties can review** — after completion, the client and provider can each leave a 1–5 star review on the order.

**Cancellation paths:**
- The **client** can cancel a `pending` or `confirmed` order (must supply a reason). Any held/charged payment is **refunded**.
- The **provider** can reject a `confirmed` or `in_progress` order (must supply a reason). Any held/charged payment is **refunded**.

---

## Supporting Infrastructure

- **NotificationService** — delivers notifications via push, SMS, and email (using `ActionMailer`) based on each user's preferences. Fires on every major order event.
- **PaymentGateway** — a simple internal service that simulates payment operations (hold, charge, refund), logging all transactions to `log/payments.log`.
- **Admin panel** — a separate set of controllers (`admin/`) for managing clients, providers, orders, and payments with a dashboard overview.
- **REST API** — a full `api/` namespace exposing endpoints for all entities to be consumed by a mobile or web client.
