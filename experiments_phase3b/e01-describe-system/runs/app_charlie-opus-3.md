# Experiment: e01-describe-system
# App: app_charlie | Model: opus | Run: 3

---

This is a **service marketplace / booking platform** built as a Rails 8.1 API application. Here's the breakdown:

## Domain

A two-sided marketplace connecting **Clients** (who need services) with **Providers** (who deliver them). The default currency is RUB, suggesting a Russian market context.

## Main Entities

- **Client** — registers, stores payment cards, creates service requests, leaves reviews
- **Provider** — registers with a specialization, has a rating, accepts/declines work
- **Card** — client's payment card (tokenized, with a default flag)
- **Request** — the core entity: a booking for a provider at a scheduled time, with duration and price
- **Payment** — tied to a request; goes through pending → held → charged (or refunded), with a fee
- **Review** — polymorphic author (client or provider), with a rating and body, tied to a request

## Request Lifecycle (State Machine)

```
pending → accepted → in_progress → completed
  │          │           │
  ├→ declined │           └→ rejected
  ├→ expired  ├→ canceled
  └→ canceled └→ rejected
```

A client creates a request for a specific provider. The provider can **accept** or **decline**. Once accepted, the provider **starts** the work, then marks it **complete**. Either party can **cancel** (before start) or **reject** (after acceptance). Unattended requests can **expire**.

## Typical Workflow

1. Client and provider register via the API (token-based auth)
2. Client adds a payment card
3. Client creates a **Request** — specifying provider, schedule, duration, amount, and location
4. Provider accepts → payment is held on the client's card
5. Provider starts and completes the service → payment is charged
6. Both parties leave reviews

The app also has a read-only **admin panel** for monitoring requests, clients, providers, and payments, plus a **NotificationService** for sending notifications based on user preferences (push/SMS/email).
