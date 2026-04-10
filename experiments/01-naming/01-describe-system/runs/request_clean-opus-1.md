# Experiment: 01-describe-system
# App: request_clean | Model: opus | Run: 1

---

This is a **service marketplace platform** — a Rails app where **clients** book time-based services from **providers** (likely derived from a childcare/babysitting domain called "Kidsout").

## Main Entities

- **Client** — a customer who books services. Has email, phone, notification preferences, and an API token for authentication. Can store multiple payment cards.
- **Provider** — a service professional (e.g., babysitter). Has a rating (0–5), specialization, and active/inactive status.
- **Request** — the central entity: a booking of a provider by a client for a scheduled time slot. Tracks duration, price (`amount_cents` in RUB), location, and notes.
- **Payment** — one-to-one with a request. Follows a hold-then-charge flow: `pending → held → charged`, with a `refunded` state available.
- **Card** — a client's stored payment card (Visa/MC/Amex/Mir). One card can be marked as default.
- **Review** — polymorphic; both clients and providers can review a completed request (rating 1–5 + text body). Each author can review a given request only once.

## Typical Workflow

1. **Client creates a Request** — picks a provider, scheduled time, duration, and amount.
2. **Provider confirms** — request moves `pending → confirmed`.
3. **Service starts** — `confirmed → in_progress`, `started_at` is recorded.
4. **Service completes** — `in_progress → completed`, `completed_at` is recorded.
5. **Payment is processed** — the associated payment is held before the session, then charged upon completion (or refunded if canceled).
6. **Reviews** — after completion, both client and provider can leave a review.

Requests can also be **canceled** (from pending/confirmed, requires a reason) or **rejected** by the provider (from confirmed/in_progress, requires a reason).

The app exposes both an **Admin** interface (dashboard, managing clients/providers/requests/payments) and a **JSON API** for client/provider-facing apps.
