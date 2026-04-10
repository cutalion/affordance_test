# Experiment: e01-describe-system
# App: app_bravo | Model: opus | Run: 2

---

This is a **service booking marketplace** — a Rails API application connecting **clients** who need services with **providers** who deliver them (think cleaning, tutoring, beauty services, etc.).

## Main Entities

- **Client** — a customer who books services. Has an API token, contact info, and notification preferences.
- **Provider** — a service professional with a specialization, rating, and active/inactive status.
- **Card** — a client's saved payment card (tokenized). One card can be marked as default.
- **Request** — a booking inquiry from a client to a specific provider, specifying time, duration, and location. State machine: `pending → accepted / declined / expired`.
- **Order** — a confirmed engagement for service delivery, with price (`amount_cents`), schedule, and location. Can originate from a Request. State machine: `pending → confirmed → in_progress → completed`, or `canceled` / `rejected` at certain stages.
- **Payment** — the financial transaction tied to an order. Follows a hold-then-charge flow: `pending → held → charged`, with a `refunded` path for cancellations. Tracks a platform fee (`fee_cents`).
- **Review** — a polymorphic rating+text left on a completed order by either the client or the provider.

## Typical Workflow

1. **Client sends a Request** to a provider for a specific date/time and duration.
2. **Provider accepts** (or declines/lets it expire).
3. **An Order is created** (either from an accepted request or directly) with pricing details.
4. **Provider confirms** the order → **starts** it when work begins → **completes** it when done.
5. **Payment is held** before the appointment, **charged** upon completion (or **refunded** on cancellation).
6. **Both parties leave Reviews** on the completed order, updating the provider's rating.

The app exposes a JSON API for client/provider mobile apps and a read-only admin panel for back-office oversight.
