# Experiment: e01-describe-system
# App: app_alpha | Model: opus | Run: 2

---

This is a **service booking / appointment request platform** built with Rails.

## Domain

A marketplace connecting **Clients** (who need services) with **Providers** (who deliver services). Think of it as a simplified booking system like a home services or consulting platform.

## Main Entities

- **Client** — registers with name/email, gets an API token, has payment cards, and submits service requests. Has configurable notification preferences (push/sms/email).
- **Provider** — registers with name/email/specialization, has a rating (0–5), can be active/inactive. Receives and responds to requests.
- **Card** — a payment card belonging to a client (brand, last four, expiry). One card can be marked as default.
- **Request** — the central entity. A client asks a specific provider for a service at a scheduled time, with a duration, location, and notes. Follows a state machine: `pending` → `accepted` / `declined` / `expired`.

## Typical Workflow

1. **Client registers** via the API and adds a payment card.
2. **Provider registers** and becomes available.
3. **Client creates a Request** — picks a provider, scheduled time, duration, location, and notes. The provider is notified.
4. **Provider responds** — either **accepts** (timestamps recorded) or **declines** (must give a reason). The client is notified of the outcome. Pending requests can also **expire**.
5. **Admin dashboard** — a read-only admin interface to browse requests, clients, and providers.

Notifications are currently stubbed — they log to a file rather than actually sending push/sms/email. Authentication is token-based (API token per client/provider).
