# Experiment: 01-describe-system
# App: request_clean | Model: opus | Run: 3

---

This is a **service booking platform** — a two-sided marketplace connecting **clients** with **providers** (likely childcare/babysitting, based on the Kidsout domain origin).

## Main Entities

- **Client** — a customer who books services. Has email, phone, notification preferences, and an API token for authentication.
- **Provider** — a service provider with a rating, specialization, and active/inactive status.
- **Request** — the central entity: a booking request from a client to a provider for a specific time, duration, location, and price.
- **Payment** — tracks the financial side of a request. Goes through `pending → held → charged` (or `refunded`). Linked to a card.
- **Card** — a stored payment card belonging to a client (brand, last four, expiry, tokenized).
- **Review** — polymorphic on `author_type` (either client or provider), tied to a request. Both sides can leave a rating + text review.

## Typical Workflow

1. **Client creates a Request** — specifying provider, scheduled time, duration, location, and amount. Starts in `pending` state.
2. **Provider confirms** — transitions to `confirmed`.
3. **Service starts** — transitions to `in_progress`, records `started_at`.
4. **Service completes** — transitions to `completed`, records `completed_at`.
5. **Payment flows in parallel** — a payment is created (pending), held before the session, charged upon completion, or refunded if canceled.
6. **Either party cancels/rejects** — `pending`/`confirmed` requests can be canceled (by client, requires reason); `confirmed`/`in_progress` can be rejected (by provider, requires reason).
7. **Reviews** — after completion, both client and provider can leave a review (one per author per request, enforced by unique index).

The app exposes both an **API** (token-authenticated, for client/provider apps) and an **admin dashboard** for back-office management.
