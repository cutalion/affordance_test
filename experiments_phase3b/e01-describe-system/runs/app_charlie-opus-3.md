# Experiment: e01-describe-system
# App: app_charlie | Model: opus | Run: 3

---

This is a **service marketplace / booking platform** — a Rails API app where clients book service providers for scheduled appointments.

## Domain

A two-sided marketplace connecting **Clients** (who need services) with **Providers** (who deliver them). Based on the Kidsout domain, this likely models something like babysitting or childcare services, though the entities are generalized.

## Main Entities

- **Client** — a customer who books services. Has payment cards, notification preferences, and API token auth.
- **Provider** — a service professional with a specialization, rating (0–5), and active/inactive status.
- **Request** — the central entity. A client creates a request for a specific provider at a scheduled time, with a duration and price. This is the booking itself.
- **Payment** — tracks money for a request. Follows a `pending → held → charged → refunded` lifecycle, with fee tracking.
- **Card** — a client's stored payment method (tokenized, with brand/last-four/expiry).
- **Review** — polymorphic by author (either client or provider can review), tied to a completed request. One review per author per request.

## Typical Workflow

1. **Client creates a Request** — specifying provider, scheduled time, duration, amount, and optional notes/location.
2. **Provider accepts or declines** — the request starts as `pending`, then transitions to `accepted` (or `declined` with a reason).
3. **Service begins** — request moves to `in_progress` when the session starts.
4. **Service completes** — request moves to `completed`.
5. **Payment flows in parallel** — a payment is created (`pending`), funds are held on the client's card (`held`), then charged upon completion (`charged`), or refunded if cancelled.
6. **Reviews** — after completion, both client and provider can leave a rating and review.

Requests can also be `canceled` (by client, before or after acceptance), `rejected` (by provider, after acceptance), or `expired` (if never accepted). The app also supports recurring bookings via `recurring_group_id`.

The app exposes both an **API** (token-authenticated, for the mobile/web client) and an **Admin** interface for back-office management.
