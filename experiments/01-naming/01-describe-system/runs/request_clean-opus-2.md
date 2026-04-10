# Experiment: 01-describe-system
# App: request_clean | Model: opus | Run: 2

---

This is a **service booking platform** — a marketplace where clients book time-based services from providers (likely inspired by a childcare/babysitting domain called "Kidsout").

## Main Entities

- **Client** — the person requesting a service. Has email, phone, notification preferences, and saved payment cards. Authenticates via API token.
- **Provider** — the person delivering the service. Has a rating, specialization, and active/inactive status. Also authenticates via API token.
- **Request** — the central entity: a booking of a provider by a client for a specific time, duration, location, and price (`amount_cents` in RUB).
- **Payment** — one-to-one with a Request. Tracks the payment lifecycle: pending → held → charged (or refunded). Linked to a client's Card.
- **Card** — a saved payment method (Visa, Mastercard, Amex, Mir) belonging to a client. One card can be marked as default.
- **Review** — a post-completion rating (1–5) with optional text. Both the client and the provider can review the same request (polymorphic `author`).

## Typical Workflow

1. **Client creates a Request** — picks a provider, scheduled time, duration, location, and agreed amount.
2. **Provider confirms** — request transitions `pending → confirmed`.
3. **Service starts** — `confirmed → in_progress`, `started_at` is recorded.
4. **Service completes** — `in_progress → completed`, `completed_at` is recorded.
5. **Payment is processed** — the associated payment moves from `pending` → `held` (pre-authorized before the session) → `charged` (after completion), or `refunded` if needed.
6. **Reviews** — once completed, both client and provider can leave a one-time review.

Requests can also be **canceled** (by the client, from pending/confirmed) or **rejected** (by the provider, from confirmed/in_progress), both requiring a reason.

The app exposes both an **API** (token-authenticated, JSON) and an **Admin** dashboard for managing all entities.
