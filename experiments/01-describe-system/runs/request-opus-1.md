# Experiment: 01-describe-system
# App: request | Model: opus | Run: 1

---

Here's a description of the system:

## Domain

This is a **service marketplace / booking platform** — a two-sided system where **Clients** book time-based services from **Providers** (think of something like a cleaning service, tutoring, beauty services, etc.). The default currency is RUB (Russian rubles), suggesting it targets the Russian market.

## Main Entities

- **Client** — A customer who books services. Has an email, name, API token, notification preferences, and can store payment cards.
- **Provider** — A service professional who fulfills requests. Has a rating (0–5), an active/inactive status, and notification preferences.
- **Request** — The central entity: a scheduled booking linking a Client to a Provider. It has a scheduled time, duration, location, notes, and an amount. It progresses through a state machine.
- **Payment** — A financial transaction tied to a Request. Follows a lifecycle: `pending → held → charged` (or `refunded`). A 10% platform fee is calculated on creation.
- **Card** — A stored payment card belonging to a Client (token, last four digits, brand, expiry). One card can be marked as default.
- **Review** — A post-fulfillment rating (1–5) that either a Client or Provider can leave on a completed Request. Each party can review only once.

## Typical Workflow

1. **Client creates a Request** — A client selects a provider, schedule, duration, and amount. A `Payment` (status: `pending`) is automatically created with a 10% fee. The provider is notified. The request starts in the `created` state.
2. **Provider accepts or declines** — The provider either `accepts` (→ `accepted`) or `declines` (→ `declined`) the request. If the provider doesn't respond, it can be marked `missed`.
3. **Service begins** — The provider `starts` the request (→ `started`), recording the start time. The client is notified.
4. **Service completed** — The provider `fulfills` the request (→ `fulfilled`), recording completion time. If a payment was held, it is charged at this point.
5. **Reviews** — After fulfillment, both client and provider can leave reviews.

**Cancellation/Rejection** can happen at various stages: clients can `cancel` (with a reason) from `created`/`accepted`, and providers can `reject` (with a reason) from `accepted`/`started`. Both trigger a refund if payment was held or charged.

There is also an alternative "direct" flow via **CreateAcceptedService**: a provider can create a request that starts in the `created_accepted` state (pre-accepted), skipping the acceptance step — useful for direct/walk-in bookings.

## Broader Context

This app (`affordance_request`) is one half of an **experiment** comparing two identical apps with different naming conventions. The sibling app (`affordance_order`) uses "Order" with clean state names (`pending`, `confirmed`, `in_progress`, `completed`), while this one uses "Request" with legacy invitation-era states (`created`, `created_accepted`, `accepted`, `started`, `fulfilled`, `declined`, `missed`). The experiment studies how entity naming affects AI reasoning about the codebase.
