# Experiment: 01-describe-system
# App: order | Model: opus | Run: 1

---

Now I have a clear picture. Here's the description:

---

## System Overview

This is a **service marketplace** platform — a Rails API application where **Clients** book **Providers** for on-demand services (originating from a babysitting marketplace concept called "Kidsout").

### Domain

A generic **service marketplace**. A client schedules a provider for a service at a specific time and location, pays for it, and can leave a review afterward.

### Main Entities

| Entity | Role |
|--------|------|
| **Client** | The customer who books and pays for services. Has an API token, notification preferences, and saved payment cards. |
| **Provider** | The service professional who fulfills orders. Has a rating, specialization, and active/inactive status. |
| **Order** | The central entity — a booking of a provider by a client. Has a scheduled time, duration, location, price, and a state machine governing its lifecycle. |
| **Card** | A saved payment card belonging to a client (tokenized, stores last four digits, brand, expiry). One card can be marked as default. |
| **Payment** | A financial transaction tied to an order. Tracks a lifecycle of `pending → held → charged` (or `refunded`). A 10% platform fee is calculated at creation. |
| **Review** | A post-completion rating (1–5) left by either a client or provider (polymorphic author). Only allowed on completed orders. |

### Typical Workflow

1. **Create** — A client creates an order for a specific provider, time, and price. A `Payment` record is created in `pending` status with a calculated fee. The provider is notified.
2. **Confirm** — The provider confirms the pending order (`pending → confirmed`).
3. **Start** — When the service begins, the order transitions to `in_progress` and `started_at` is recorded.
4. **Complete** — When the service finishes, the order moves to `completed` and `completed_at` is recorded. The payment is charged.
5. **Review** — Both client and provider can leave a review on completed orders.

Alternative flows:
- **Cancel** — A client (or provider) can cancel from `pending` or `confirmed` states (requires a reason).
- **Reject** — A provider can reject from `confirmed` or `in_progress` states (requires a reason).

### Broader Context — The Experiment

This app is actually **one half of an experiment** about how entity naming affects AI reasoning. There are two structurally identical Rails apps:

- **`affordance_order/`** (this app) — Uses clean, intuitive naming: `Order` with states `pending → confirmed → in_progress → completed`.
- **`affordance_request/`** — Uses legacy naming: `Request` with muddier states like `created`, `created_accepted`, `accepted`, `started`, `fulfilled`, `declined`, `missed`.

The experiment measures whether an AI agent reasons differently (better or worse) about the same system depending on whether the central entity is called "Order" or "Request". The `experiments/` directory contains runner scripts and analysis tooling for this research.
