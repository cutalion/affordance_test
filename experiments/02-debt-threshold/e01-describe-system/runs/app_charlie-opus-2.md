# Experiment: e01-describe-system
# App: app_charlie | Model: opus | Run: 2

---

This is a **service marketplace / on-demand booking platform** built with Rails (API + admin panel).

## Domain

A two-sided marketplace connecting **Clients** (who need a service) with **Providers** (who deliver it). Providers have specializations and ratings. The default currency is RUB, suggesting a Russian market context.

## Main Entities

| Entity | Role |
|--------|------|
| **Client** | Requests services, holds payment cards, leaves reviews |
| **Provider** | Accepts/declines/performs service requests, has a rating and specialization |
| **Request** | The core entity — a scheduled booking between a client and a provider, with time, location, duration, and price |
| **Payment** | Tracks money flow for a request (hold → charge → possible refund) |
| **Card** | A client's stored payment card (tokenized), one can be marked default |
| **Review** | Post-completion rating (1–5) + text, written by either client or provider |

## Typical Workflow

1. **Client creates a Request** — picks a provider, schedules a time/location, sets duration and amount. The provider is notified.
2. **Provider accepts** (or **declines** with a reason). Pending requests can also **expire** or be **canceled** by the client.
3. **On accept** — a Payment is created and the client's default card is **held** (pre-authorized).
4. **Provider starts** the service (request moves to `in_progress`).
5. **Provider completes** the service — the held payment is automatically **charged**, and both parties are notified.
6. **Either party can leave a Review** once the request is completed.

Alternative flows: the client can **cancel** (pending/accepted), the provider can **reject** (accepted/in_progress) — both triggering a payment **refund** if funds were held.

The app also has a read-only **admin panel** for viewing dashboard stats, requests, clients, providers, and payments.
