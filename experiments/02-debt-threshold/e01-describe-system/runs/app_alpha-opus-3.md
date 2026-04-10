# Experiment: e01-describe-system
# App: app_alpha | Model: opus | Run: 3

---

This is a **service booking/appointment platform** built with Rails.

## Domain

A marketplace where **clients** book time-based services from **providers** (think: home services, consultations, tutoring — the specific service type is generic).

## Main Entities

- **Client** — a person who requests services. Has an email, phone, API token for authentication, notification preferences (push/sms/email), and payment cards.
- **Provider** — a service professional who fulfills requests. Has a rating (0–5), specialization, active flag, and their own notification preferences.
- **Request** — the core entity: a booking from a client to a specific provider, with a scheduled time, duration, location, and notes. Has a state machine: `pending → accepted | declined | expired`.
- **Card** — a client's stored payment card (tokenized, with brand/last-four/expiry). One card can be marked as default.

## Typical Workflow

1. **Client registers** via the API and adds payment cards.
2. **Client creates a Request** — picks a provider, time slot, duration, location. The request starts in `pending` state. The provider is notified.
3. **Provider responds** — either **accepts** (client gets notified) or **declines** with a reason. Requests can also **expire** if the provider doesn't respond.
4. **Admin dashboard** — a read-only admin panel for viewing requests, clients, and providers.

Authentication is token-based (API tokens on both client and provider). Notifications are currently stubbed — they log to a file rather than actually sending push/sms/email.
