# Experiment: e01-describe-system
# App: app_alpha | Model: opus | Run: 2

---

Here's what this system does:

## Domain: Service Booking Platform

This is a **client-to-provider booking system** — think of it like a marketplace where clients book time slots with service providers (derived from a childcare/kids-activity domain called "Kidsout").

## Main Entities

- **Client** — a customer who books services. Has an email, name, API token for authentication, notification preferences, and payment cards.
- **Provider** — a service provider who fulfills requests. Has a rating (0-5), active/inactive status, and notification preferences.
- **Request** — the central entity. Represents a booking request from a client to a specific provider for a given time slot (`scheduled_at` + `duration_minutes`) at a location. Has a state machine lifecycle.
- **Card** — a client's saved payment card (visa/mastercard/amex/mir). One card can be marked as default.

## Typical Workflow

1. **Client creates a Request** — via `Requests::CreateService`, specifying a provider, scheduled time, duration, location, and notes. The provider is notified.
2. **Provider accepts or declines:**
   - **Accept** (`Requests::AcceptService`) — transitions the request from `pending` → `accepted`, records `accepted_at`, notifies the client.
   - **Decline** (`Requests::DeclineService`) — requires a reason, transitions `pending` → `declined`, notifies the client.
3. **Expiration** — pending requests that aren't acted on can transition to `expired`.

The state machine is: `pending` → `accepted` | `declined` | `expired`.

Notifications (push/sms/email) are sent based on each recipient's preferences, currently stubbed to a log file.

## Notable Details

- No API controllers are defined yet — only models and services exist.
- Authentication is token-based (API tokens on both Client and Provider).
- The `Paginatable` concern is mixed into Request for list queries.
- There are filtering scopes on Request: by state, client, provider, date range.
