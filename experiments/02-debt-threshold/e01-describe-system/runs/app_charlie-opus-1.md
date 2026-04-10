# Experiment: e01-describe-system
# App: app_charlie | Model: opus | Run: 1

---

This is a **service marketplace / on-demand booking platform** built with Rails.

## Domain

A two-sided marketplace connecting **Clients** (who request services) with **Providers** (who fulfill them). Think of it like an Uber-style model — a client books a provider for a scheduled time slot and pays via a stored card.

## Main Entities

| Entity | Role |
|---|---|
| **Client** | Registers, stores payment cards, creates service requests, leaves reviews |
| **Provider** | Registers, accepts/declines requests, delivers the service, has a rating |
| **Card** | A client's stored payment method (tokenized, with brand/last-four/expiry), one marked as default |
| **Request** | The core transaction — a scheduled booking with amount, duration, and a state machine lifecycle |
| **Payment** | Tracks money flow for a request: pending → held → charged (or refunded) |
| **Review** | Post-completion rating (1–5) left by either the client or provider |

## Typical Workflow

1. **Registration** — Client and Provider sign up and receive API tokens.
2. **Card setup** — Client adds a payment card and marks one as default.
3. **Booking** — Client creates a **Request** specifying a provider, scheduled time, duration, and amount. It starts in `pending` state.
4. **Provider response** — Provider either **accepts** or **declines** the request (with a reason). Unhandled requests can **expire**.
5. **Service delivery** — Once accepted, the provider **starts** the request (moves to `in_progress`), then **completes** it.
6. **Cancellation/rejection** — Either party can **cancel** (from pending/accepted) or the provider can **reject** (from accepted/in_progress), both requiring a reason.
7. **Payment** — A payment record tracks the charge lifecycle: hold → charge on completion, or refund on cancellation.
8. **Review** — After completion, both client and provider can leave a one-time review with a 1–5 rating.

There's also a read-only **Admin** panel for viewing requests, clients, providers, and payments.
