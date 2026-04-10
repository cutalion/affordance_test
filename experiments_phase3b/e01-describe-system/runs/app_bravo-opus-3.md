# Experiment: e01-describe-system
# App: app_bravo | Model: opus | Run: 3

---

This is a **service marketplace / booking platform** built with Rails (API-mode + admin panel). Here's the breakdown:

## Domain

A two-sided marketplace where **clients** book time-based services from **providers** (specialists). The currency is RUB, and providers have specializations and ratings — think something like a home services or professional consultations platform.

## Main Entities

- **Client** — the customer who books services. Has payment cards, notification preferences, and API token auth.
- **Provider** — the service professional. Has a specialization, rating, and active/inactive status.
- **Request** — a booking inquiry from a client to a specific provider. States: `pending → accepted / declined / expired`.
- **Order** — a confirmed engagement. Created when a request is accepted (or directly). States: `pending → confirmed → in_progress → completed`, or `canceled / rejected`.
- **Payment** — one per order, with a 10% platform fee. Lifecycle: `pending → held → charged → refunded`.
- **Card** — stored payment cards for clients (tokenized with brand/last four).
- **Review** — polymorphic (both clients and providers can author), tied to an order, with a 1-5 rating.

## Typical Workflow

1. **Client creates a Request** to a specific provider, specifying schedule, duration, and location.
2. **Provider accepts or declines** the request. Accepting automatically creates an **Order** (with a hardcoded 350,000 kopecks / 3,500 RUB price) and a **Payment** record.
3. The order moves through **confirm → start → complete** as the service is delivered.
4. The payment follows its own lifecycle: **hold → charge** (or refund on cancellation).
5. After completion, either party can leave a **Review**.

Notifications are sent at key transitions (request created, accepted, order created, etc.) via a `NotificationService`. There's also a read-only **admin panel** for viewing all entities.
