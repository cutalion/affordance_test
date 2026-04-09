# Experiment: e01-describe-system
# App: app_charlie | Model: opus | Run: 1

---

This is a **service marketplace** — a two-sided platform connecting **Clients** with **Providers** for scheduled, on-location services (derived from a kids' entertainment/activity booking domain called "Kidsout").

## Main Entities

- **Client** — a customer who books and pays for services. Has name, email, phone, notification preferences, and an API token for authentication.
- **Provider** — a service professional with a specialization, rating, and active/inactive status. Also authenticated via API token.
- **Request** — the central entity. A Client creates a Request for a specific Provider at a scheduled time, location, duration, and price (`amount_cents`). Supports recurring bookings via `recurring_group_id`.
- **Card** — a Client's saved payment card (brand, last four, expiry, tokenized). One card can be marked as default.
- **Payment** — tracks the financial lifecycle of a Request: pending → held → charged (or refunded). Includes platform fees (`fee_cents`).
- **Review** — polymorphic (either Client or Provider can be the author). One review per author per Request, with a numeric rating and optional text body.

## Typical Workflow

1. **Client creates a Request** — specifying provider, schedule, duration, location, and amount.
2. **Provider accepts or declines** — declining requires a reason. If neither happens in time, the request can expire.
3. **Provider starts the service** — transitions the request to `in_progress`.
4. **Provider completes the service** — marks it `completed`, triggering payment processing (hold → charge).
5. **Either party can cancel** (before start, with a reason) or the **provider can reject** (after accepting, with a reason).
6. **Both parties leave reviews** after completion.

The state machine is: `pending → accepted → in_progress → completed`, with branches to `declined`, `expired`, `canceled`, and `rejected`.

The app exposes a JSON API for clients/providers and a read-only admin panel for back-office oversight (dashboard, requests, clients, providers, payments). Business logic lives in service objects under `Requests::*Service`.
