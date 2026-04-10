# Experiment: 01-describe-system
# App: order | Model: opus | Run: 3

---

Here's a description of the system:

## Domain

This is a **service booking and order management platform** — a Rails 8.1 application for scheduling appointments between **clients** and **service providers**. The default currency is RUB (Russian rubles), suggesting it targets the Russian market. Think of it as a backend for something like a home-services or beauty-services marketplace (e.g., booking a plumber, cleaner, tutor, etc.).

## Main Entities

1. **Client** — A customer who books services. Has email, name, phone, an API token for authentication, notification preferences, and can store multiple payment cards.

2. **Provider** — A service professional who fulfills orders. Has a specialization, a rating (0–5), an active/inactive flag, and notification preferences.

3. **Order** — The central entity. Represents a scheduled service appointment between a client and a provider. Key attributes include: scheduled time, duration, location, notes, amount (in cents), and a state machine governing its lifecycle.

4. **Card** — A saved payment card belonging to a client (tokenized, storing only last four digits, brand, expiry). One card per client can be marked as the default.

5. **Payment** — Linked 1:1 to an order. Tracks the money flow with statuses: `pending → held → charged` (or `refunded`). Also tracks a `fee_cents` field (platform commission).

6. **Review** — A polymorphic review that can be authored by either a client or a provider after an order is completed. Each party can leave one review per order (rating 1–5 + optional text).

## Typical Workflow

1. **Booking**: A client creates an **Order** for a specific provider, choosing a time slot, duration, and location. The order starts in the **`pending`** state.

2. **Confirmation**: The provider (or an admin) **confirms** the order → state becomes **`confirmed`**.

3. **Payment hold**: Before the appointment, a **Payment** is created (linked to the client's card). Funds are **held** (`pending → held`) — typically within 24 hours of the scheduled time.

4. **Service delivery**: At the scheduled time, the order is **started** → **`in_progress`** (records `started_at`).

5. **Completion**: After the service is rendered, the order is **completed** → **`completed`** (records `completed_at`). The held payment is then **charged**.

6. **Cancellation / Rejection**: At various points the order can be **canceled** (by the client, from `pending` or `confirmed` states, with a reason) or **rejected** (by the provider, from `confirmed` or `in_progress`, with a reason). In these cases, the payment may be **refunded**.

7. **Review**: Once an order is completed, both the client and the provider can leave a **review** with a 1–5 star rating.

The system exposes both an **API** (for client/provider mobile or web apps, authenticated via API tokens) and an **Admin** interface (with dashboard, order/payment/provider management).
