# Experiment: e01-describe-system
# App: app_delta | Model: opus | Run: 1

---

This is a **service marketplace platform** — a two-sided marketplace connecting **Clients** (who need services) with **Providers** (who deliver them). The domain appears derived from a childcare/kids-activities context (Kidsout), generalized into neutral naming.

## Main Entities

- **Client** — a customer who needs a service. Has payment cards, notification preferences.
- **Provider** — a service professional with a rating, specialization, and active/inactive status.
- **Card** — a client's stored payment card (tokenized, with last-four, brand, expiry).

## Two Booking Flows

**1. Direct Request (client → specific provider)**
- **Request** — a client asks a specific provider for a booking at a given time/duration/location. State machine: `pending → accepted/declined/expired`.
- If accepted, it can lead to an **Order**.

**2. Open Announcement (client → marketplace)**
- **Announcement** — a client posts an open listing (title, description, budget, schedule). State machine: `draft → published → closed`.
- **Response** — a provider bids on an announcement with an optional proposed price. State machine: `pending → selected/rejected`. One response per provider per announcement.
- A selected response can also lead to an Order.

## Fulfillment & Payment

- **Order** — the confirmed booking, linked to a client, provider, and optionally a request. Has pricing (`amount_cents`, `currency: RUB`). State machine: `pending → confirmed → in_progress → completed`, with `canceled`/`rejected` branches.
- **Payment** — tracks money flow for an order. Status lifecycle: `pending → held → charged`, with a `refunded` path. Supports hold-then-charge (pre-authorization before the service starts).
- **Review** — polymorphic author (client or provider) leaves a rating + text on a completed order. One review per author per order.

## Typical Workflow

1. **Client registers**, adds a payment card
2. **Option A**: Client sends a **Request** to a specific provider → provider accepts → **Order** is created
3. **Option B**: Client creates an **Announcement** → publishes it → providers submit **Responses** → client selects a response → **Order** is created
4. Order is **confirmed** → **started** → **completed**
5. **Payment** is held before the service, charged on completion (or refunded on cancellation)
6. Both parties leave **Reviews**

The API is token-authenticated (via `api_token` on clients/providers), with a read-only **Admin** panel for dashboard, browsing orders, requests, clients, providers, payments, and announcements.
