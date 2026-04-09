# Experiment: e01-describe-system
# App: app_alpha | Model: opus | Run: 1

---

Here's what this system does:

## Domain

This is a **service booking marketplace** — a platform where **clients** book time with **providers** (likely derived from a childcare/babysitting domain called "Kidsout," but abstracted to generic names).

## Main Entities

- **Client** — a customer who requests services. Has email, phone, notification preferences, and an API token for authentication.
- **Provider** — a service professional. Has a rating, specialization, active status, and similar auth/notification fields.
- **Request** — the core transaction. A client asks a specific provider for a booking at a scheduled time, for a given duration, at a location. Requests follow a state machine: `pending → accepted / declined / expired`.
- **Card** — payment cards belonging to a client (brand, last four, expiry, token). One can be marked as default.

## Typical Workflow

1. **Registration** — Clients and providers register via the API and receive an API token.
2. **Client creates a Request** — specifying a provider, scheduled time, duration, location, and optional notes.
3. **Provider responds** — they either **accept** (timestamps `accepted_at`) or **decline** (with a `decline_reason`). If neither happens in time, the request can **expire**.
4. **Payment cards** — clients manage saved payment cards, setting one as default.
5. **Admin dashboard** — read-only admin views for monitoring clients, providers, and requests.

The architecture is a JSON API (namespaced under `api/`) with token-based auth, plus a separate admin namespace for back-office visibility.
