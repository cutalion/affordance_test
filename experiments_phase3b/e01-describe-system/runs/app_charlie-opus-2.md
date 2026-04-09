# Experiment: e01-describe-system
# App: app_charlie | Model: opus | Run: 2

---

Here's what this system does:

## Domain: On-Demand Service Marketplace

This is a **service booking platform** (derived from a childcare/babysitting domain like "Kidsout") where **clients** book time with **providers** (service professionals). Think of it like an Uber-style marketplace but for scheduled services.

## Main Entities

- **Client** — a person who books services. Has an email, phone, API token for auth, notification preferences, and saved payment cards.
- **Provider** — a professional who fulfills requests. Has a rating, specialization, and active/inactive status.
- **Request** — the central entity. A booking for a provider's time at a specific date/location, with a price (`amount_cents`) and duration. Supports recurring bookings via `recurring_group_id`.
- **Payment** — tracks money flow for a request. Follows a hold-then-charge model (pending → held → charged), with refund support.
- **Card** — a saved payment method (Visa, Mastercard, Amex, Mir) belonging to a client. One card can be marked as default.
- **Review** — polymorphic; both clients and providers can review each other after a completed request. Rating 1-5 with optional body text.

## Typical Workflow

1. **Client creates a Request** — picks a provider, date/time, duration, location, and amount.
2. **Provider accepts or declines** — a pending request can be accepted, declined (with reason), or it expires automatically.
3. **Service starts** — an accepted request transitions to `in_progress`.
4. **Service completes** — marked as completed, triggering payment processing (hold → charge).
5. **Reviews** — after completion, both parties can leave a review.

Requests can also be **canceled** by the client (from pending/accepted) or **rejected** by the provider (from accepted/in_progress), each requiring a reason.

## Architecture

- **API layer** (`/api`) — token-authenticated JSON API for clients and providers (registration, booking, payments, reviews).
- **Admin layer** (`/admin`) — read-only dashboard for managing/viewing requests, clients, providers, and payments.
- **Service objects** (`app/services/requests/*`) — each state transition has its own service class, keeping controllers thin.
- **State machine** — the Request model uses AASM for a well-defined lifecycle with guarded transitions.
