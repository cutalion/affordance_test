# Experiment: e01-describe-system
# App: app_bravo | Model: opus | Run: 2

---

This is a **service booking marketplace** — a two-sided platform connecting **Clients** with **Providers** (likely derived from a childcare/babysitting domain like "Kidsout").

## Main Entities

- **Client** — a person who books services. Has payment cards, notification preferences, and an API token for authentication.
- **Provider** — a service professional with a specialization, rating, and active/inactive status.
- **Request** — a booking inquiry from a Client to a specific Provider for a time slot and duration. States: `pending → accepted / declined / expired`.
- **Order** — the confirmed engagement with pricing. Can originate from a Request or be created directly. States: `pending → confirmed → in_progress → completed` (or `canceled` / `rejected`). Tracks amount, currency (RUB), location, and notes.
- **Payment** — tied 1:1 to an Order. Follows a hold-then-charge flow: `pending → held → charged` (or `refunded`). Linked to a client's Card.
- **Card** — a stored payment method (brand, last four, expiry, token). One card per client can be marked as default.
- **Review** — polymorphic (both clients and providers can author). Tied to a completed Order, with a numeric rating and text body. One review per author per order.
- **RecurringBooking** — a template for repeated sessions between a Client and Provider (with a `sessions_count`), which generates individual Requests.

## Typical Workflow

1. **Client creates a Request** to a Provider for a specific date/time and duration.
2. **Provider accepts** (or declines/lets it expire). Acceptance transitions the Request to `accepted`.
3. **An Order is created** from the accepted Request, with pricing (`amount_cents`) and scheduling details.
4. **Payment is held** against the client's card before the session.
5. **Order progresses**: `confirmed → in_progress → completed` as the session happens.
6. **Payment is charged** upon completion (or refunded if canceled).
7. **Both parties leave Reviews** on the completed Order.

The app exposes both an **API** (token-authenticated, for client/provider mobile apps) and an **Admin** interface (for back-office management of all entities).
