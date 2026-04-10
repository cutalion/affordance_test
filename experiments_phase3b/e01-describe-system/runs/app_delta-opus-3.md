# Experiment: e01-describe-system
# App: app_delta | Model: opus | Run: 3

---

This is a **service marketplace platform** (Rails 8.1) that connects **clients** with **service providers** — think of it as a booking system for on-demand services (similar to cleaning, tutoring, or personal services).

## Main Entities

- **Client** — person who needs a service. Has saved payment cards and notification preferences.
- **Provider** — person who delivers a service. Has a specialization, rating, and active status.
- **Card** — a client's saved payment method (tokenized).

## Two Ways to Book

**1. Direct Request (client → specific provider)**
- **Request** — a client asks a specific provider for a time slot (`pending → accepted / declined / expired`). If accepted, it leads to an Order.

**2. Announcement (client → open market)**
- **Announcement** — a client posts a job to the marketplace (`draft → published → closed`).
- **Response** — providers bid on the announcement with a proposed price and message (`pending → selected / rejected`). The client picks a winner.

## Fulfillment

- **Order** — the confirmed booking between a client and provider (`pending → confirmed → in_progress → completed`, or `canceled / rejected`). Can originate from either a Request or an Announcement.
- **Payment** — tracks money for an order with hold/charge/refund lifecycle (`pending → held → charged`, or `refunded`). Includes a platform fee.
- **Review** — polymorphic; both client and provider can review each other after order completion.

## Typical Workflow

1. Client creates a **Request** to a specific provider (or publishes an **Announcement** for bids)
2. Provider **accepts** the request (or submits a **Response** to the announcement, client **selects** one)
3. An **Order** is created with the agreed amount, time, and location
4. The order is **confirmed**, a **Payment** hold is placed on the client's card
5. Provider **starts** and then **completes** the order
6. Payment is **charged**
7. Both parties leave **Reviews**

The platform takes a fee on each payment and has an admin panel for managing clients, providers, orders, payments, requests, and announcements.
