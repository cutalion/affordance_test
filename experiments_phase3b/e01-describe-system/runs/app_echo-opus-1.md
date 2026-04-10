# Experiment: e01-describe-system
# App: app_echo | Model: opus | Run: 1

---

Here's what this system does:

## Domain

This is a **service marketplace platform** — a Rails API that connects **clients** who need services with **providers** who deliver them. The default currency (RUB) suggests a Russian market. Think of it as a booking/scheduling system similar to platforms for home services, tutoring, or freelance work.

## Main Entities

- **Client** — a customer who books services, has payment cards on file, and can post announcements
- **Provider** — a service professional with a rating (0-5), who accepts/declines work requests
- **Request** — the central entity; a scheduled service booking between a client and a provider, with a time, duration, location, and price
- **Announcement** — a client-posted listing (draft -> published -> closed) that providers can respond to, generating requests
- **Payment** — tracks money for a request through a lifecycle: pending -> held -> charged (or refunded)
- **Card** — a client's stored payment method (visa/mastercard/amex/mir), with one default card
- **Review** — post-completion ratings (1-5) that either party can leave on a completed request

## Typical Workflow

1. **Client creates a request** — specifying a provider, schedule, duration, location, and price. The provider gets notified.
2. **Provider accepts or declines** — declining requires a reason. Pending requests can also expire or be canceled by the client.
3. **Provider starts the work** — transitions the accepted request to in-progress; the client is notified.
4. **Provider completes the work** — if a payment was held, it gets charged automatically. Both parties are notified.
5. **Either party leaves a review** — only possible on completed requests, one review per author per request.

Alternatively, a provider can **reject** an accepted/in-progress request (with a reason), which triggers a refund if payment was held or charged.

There's also an **announcements** flow where clients publish listings that can generate requests from interested providers.

The system exposes both an **API** (token-authenticated, for client/provider apps) and an **admin panel** (HTTP basic auth, for managing clients, providers, and payments).
