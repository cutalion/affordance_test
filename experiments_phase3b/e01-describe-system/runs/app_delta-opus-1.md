# Experiment: e01-describe-system
# App: app_delta | Model: opus | Run: 1

---

This is a **service marketplace platform** — a Rails app that connects **clients** who need services with **providers** who deliver them. Think of it like a booking platform (similar to a freelance services marketplace or appointment-booking system). Currency defaults to RUB, suggesting a Russian market.

## Main Entities

- **Client** — a person who needs a service. Has saved payment cards and notification preferences.
- **Provider** — a service professional. Has a specialization, rating, and active/inactive status.
- **Card** — a client's saved payment card (tokenized).

## Two Booking Flows

**1. Direct Request (client-initiated)**
- **Request** — a client sends a booking request directly to a specific provider (with schedule, duration, location).
- The provider can **accept** or **decline**; unhandled requests **expire**.
- Accepting a request leads to creating an **Order**.

**2. Announcement (broadcast/bidding)**
- **Announcement** — a client posts a job announcement (draft → published → closed) with a budget, description, schedule, and location.
- **Response** — providers respond to announcements, optionally proposing a different price. The client can **select** one response or **reject** others. Selecting a response also leads to an Order.

## Order Lifecycle

**Order** follows a state machine: `pending → confirmed → in_progress → completed`, with `canceled` and `rejected` as terminal states. Each order has:
- **Payment** — tracks money flow with states for pending, held, charged, and refunded.
- **Review** — polymorphic (both client and provider can leave reviews with a rating and body).

## Typical Workflow

1. Client either sends a **Request** to a specific provider, or publishes an **Announcement** for providers to bid on.
2. Provider accepts the request (or client selects a provider's response to an announcement).
3. An **Order** is created with amount, schedule, and duration.
4. A **Payment** is created (hold → charge flow via a payment gateway).
5. The order progresses: confirmed → started → completed.
6. Both parties can leave **Reviews**.

Notifications are sent at key state transitions via a `NotificationService`.
