# Experiment: e01-describe-system
# App: app_bravo | Model: opus | Run: 3

---

This is a **service booking marketplace** — a two-sided platform connecting **Clients** (who need services) with **Providers** (who deliver them). The domain is derived from a childcare/babysitting marketplace (Kidsout).

## Main Entities

- **Client** — a person who books services. Has payment cards, notification preferences, and an API token for authentication.
- **Provider** — a service professional with a specialization, rating, and active/inactive status.
- **Request** — a client's initial ask to book a provider for a specific time, duration, and location. State machine: `pending → accepted / declined / expired`.
- **Order** — the confirmed engagement that gets created after a request is accepted (or directly). Tracks amount, schedule, and has a richer state machine: `pending → confirmed → in_progress → completed`, with `canceled` and `rejected` side-exits.
- **Payment** — tied to an order. Follows a hold-then-charge flow: `pending → held → charged`, with `refunded` as an alternative outcome.
- **Card** — a client's stored payment method (tokenized, with brand/last-four/expiry).
- **Review** — polymorphic (both clients and providers can author reviews), tied to a completed order.
- **RecurringBooking** — a template for generating multiple requests for the same client/provider pair on a recurring schedule.

## Typical Workflow

1. **Client creates a Request** for a specific provider, date/time, duration, and location.
2. **Provider accepts or declines** the request (or it expires).
3. On acceptance, an **Order** is created (linked to the request), initially `pending`.
4. The order is **confirmed**, a **Payment** is created and **held** against the client's card.
5. At the scheduled time, the order transitions to **in_progress** (started).
6. When the session ends, the order is **completed**, and the payment is **charged**.
7. Either party can leave a **Review** on the completed order.

Cancellations (by client) and rejections (by provider) can happen before or during the engagement, with corresponding payment refunds.

The app exposes both an **API** (token-authenticated, for client/provider apps) and an **Admin** interface (dashboard, CRUD for all entities).
