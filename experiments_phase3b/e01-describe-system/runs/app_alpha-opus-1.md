# Experiment: e01-describe-system
# App: app_alpha | Model: opus | Run: 1

---

This is a **service booking/appointment platform** built as a Rails 8.1 API application. Here's the breakdown:

## Domain

A marketplace connecting **clients** with **service providers**, where clients can book time-based appointments.

## Main Entities

- **Client** — a customer who registers, stores payment cards, and books appointments. Authenticated via `api_token`. Has notification preferences (push/sms/email).
- **Provider** — a service professional with a specialization and rating. Can be active/inactive. Also authenticated via `api_token`.
- **Card** — a client's payment card (tokenized, storing brand/last four/expiry). One can be marked as `default`.
- **Request** — the core entity: a booking request from a client to a provider, with a scheduled time, duration, location, and notes. Has a state machine: `pending → accepted / declined / expired`.

## Typical Workflow

1. Clients and providers **register** via the API
2. A client **adds a payment card** and optionally sets one as default
3. A client **creates a request** to a specific provider — specifying when, how long, where, and any notes
4. The provider is **notified** (push/sms/email, based on preferences)
5. The provider **accepts** or **declines** the request (with a reason). Pending requests can also **expire**.
6. An **admin dashboard** provides read-only oversight of all requests, clients, and providers

The notification system currently logs to a file rather than sending real messages — it's either stubbed or early-stage.
