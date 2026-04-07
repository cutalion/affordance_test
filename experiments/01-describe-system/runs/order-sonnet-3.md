# Experiment: 01-describe-system
# App: order | Model: sonnet | Run: 3

---

I now have a thorough understanding of the system. Here's the full description:

---

## Domain

This is a **service booking and order management platform** — a marketplace that connects **clients** (service consumers) with **providers** (service professionals). The currency defaults to RUB (Russian Rubles), and the overall structure resembles an on-demand service app (like a home services, beauty, or task marketplace).

---

## Main Entities

| Entity | Description |
|---|---|
| **Client** | A consumer who books services. Has an email, phone, API token for authentication, saved payment cards, and configurable notification preferences (push, SMS, email). |
| **Provider** | A service professional who fulfills orders. Has a specialization, a rating (0–5), an active/inactive status, and the same notification preferences as clients. |
| **Order** | The core entity — represents a booked appointment between a client and a provider. Has a scheduled time, duration, location, notes, price, and moves through a state machine. |
| **Payment** | Created automatically with each order. Tracks the financial transaction (hold → charge → refund) and is linked to the client's card. A 10% platform fee is calculated at creation. |
| **Card** | A saved payment method belonging to a client. Stores brand, last four digits, expiry, and a tokenized reference. One card can be marked as the default. |
| **Review** | A post-completion rating (1–5 stars with optional text). Both clients and providers can leave a review on a completed order, but only once each. |

---

## Typical Workflow

### Order Lifecycle (State Machine)

```
pending → confirmed → in_progress → completed
    ↓          ↓            ↓
 canceled   canceled     rejected
             rejected
```

1. **Client creates an order** — specifies provider, scheduled time, duration, location, and price. A `Payment` record is created simultaneously in `pending` status with a 10% fee. The provider receives a notification.

2. **Provider confirms the order** — transitions to `confirmed`. The client is notified. *(At some point before the scheduled time, a background job places a **hold** on the client's default card.)*

3. **Provider starts the order** — transitions to `in_progress`, recording `started_at`. The client is notified.

4. **Provider completes the order** — transitions to `completed`, recording `completed_at`. If the payment is on hold, it is **charged** at this point. Both parties are notified.

5. **Post-completion** — both client and provider can leave a **review** for the order.

### Cancellation / Rejection Paths

- **Client cancels** (from `pending` or `confirmed`): must provide a reason; any held/charged payment is **refunded**; provider is notified.
- **Provider rejects** (from `confirmed` or `in_progress`): must provide a reason; any held/charged payment is **refunded**; client is notified.

---

## Supporting Infrastructure

- **API layer** (`/api/*`) — Token-authenticated REST API for both clients and providers to register, manage cards, and interact with orders, payments, and reviews.
- **Admin panel** (`/admin/*`) — Read-only dashboard for viewing orders, clients, providers, and payments.
- **Background jobs** — `PaymentHoldJob` (holds funds before the scheduled appointment) and `ReviewReminderJob` (prompts users to leave reviews after completion).
- **NotificationService** — Delivers notifications via push, SMS, and email based on each user's preferences.
- **PaymentGateway** — A stub/log-based payment processor handling hold, charge, and refund operations.
