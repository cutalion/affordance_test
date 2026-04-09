# Experiment: e01-describe-system
# App: app_alpha | Model: opus | Run: 3

---

Here's what this system does:

## Domain

This is a **service booking marketplace** — a two-sided platform where **Clients** book time with **Providers**. Based on the memory and repo context, the domain is derived from "Kidsout" (likely a childcare/babysitting service), but the app uses generic naming.

## Main Entities

- **Client** — A customer who creates service requests. Has an email, phone, API token for authentication, and notification preferences (push/sms/email). Can store multiple payment cards.
- **Provider** — A service provider who fulfills requests. Has a specialization, rating (0–5), active/inactive status, and their own API token and notification preferences.
- **Request** — The central entity connecting a Client to a Provider. Represents a booking for a specific time (`scheduled_at`), duration (`duration_minutes`), and location. Has a state machine with four states.
- **Card** — A stored payment card belonging to a Client (brand, last four digits, expiration, tokenized). One card can be marked as the default.

## Typical Workflow

1. A **Client** creates a **Request**, specifying a provider, scheduled time, duration, location, and optional notes.
2. The Request starts in **`pending`** state.
3. The **Provider** can:
   - **Accept** it → transitions to `accepted`, records `accepted_at` timestamp
   - **Decline** it → transitions to `declined`, requires a `decline_reason`
4. If neither happens, the request can **expire** → transitions to `expired`, records `expired_at`.

## API Surface

The app exposes two interfaces:
- **API** (`api/`) — token-authenticated endpoints for clients, providers, requests, and cards (programmatic access)
- **Admin** (`admin/`) — dashboard plus management of requests, clients, and providers
