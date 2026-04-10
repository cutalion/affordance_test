# Experiment: e01-describe-system
# App: app_delta | Model: opus | Run: 2

---

This is a **service marketplace platform** — a Rails API for connecting **clients** with **service providers** (likely for personal/home services, given the scheduling, location, and duration-based structure). The currency is RUB (Russian rubles).

## Main Entities

- **Client** — a person who needs a service. Has payment cards, can create requests/orders/announcements, and leave reviews.
- **Provider** — a service professional with a specialization and rating. Accepts requests, fulfills orders, responds to announcements.
- **Request** — a direct booking inquiry from a client to a specific provider. States: `pending → accepted / declined / expired`. Accepting auto-creates an Order.
- **Announcement** — a broadcast-style "job posting" by a client. States: `draft → published → closed`. Providers submit Responses to compete for the work.
- **Response** — a provider's bid on an announcement, optionally with a proposed price. States: `pending → selected / rejected`.
- **Order** — the core transactional entity: a confirmed service engagement between a client and provider, with scheduled time, location, duration, and price. States: `pending → confirmed → in_progress → completed` (or `canceled / rejected`). Automatically creates a Payment.
- **Payment** — tracks the money flow for an order (with a 10% platform fee). States: `pending → held → charged → refunded`.
- **Card** — a client's stored payment card (with a default-card mechanism).
- **Review** — polymorphic; both clients and providers can review each other after an order is completed (rating 1–5).

## Typical Workflows

1. **Direct booking**: Client creates a **Request** to a specific provider → Provider **accepts** (auto-creates an Order + Payment) or **declines** → Order progresses through confirm → start → complete → both parties leave Reviews.

2. **Announcement/bidding**: Client creates an **Announcement** and publishes it → Providers submit **Responses** (bids) → Client **selects** a response (or rejects others) → (presumably an Order is created from the selected response).

3. **Payment lifecycle**: When an Order is created, a Payment is created in `pending` status with a 10% fee. It can then be held, charged on completion, or refunded on cancellation.

There's also an **admin panel** (read-only views) for monitoring all entities.
