# Experiment: e02-happy-path
# App: app_alpha | Model: opus | Run: 1

---

The main entity is **Request**. Here's the happy path, step by step:

1. **Client and Provider exist** — A `Client` (with email, name, API token, and optionally a default `Card`) and an active `Provider` (with email, name, rating) are already registered in the system.

2. **Request is created** (`pending`) — The client creates a Request linked to a specific provider, with a `scheduled_at` datetime and `duration_minutes`. It starts in the **pending** state.

3. **Provider accepts** (`pending` → `accepted`) — The provider reviews the request and calls `accept!`. The state transitions to **accepted** and `accepted_at` is recorded with the current timestamp.

That's it — **pending → accepted** is the happy path. Two steps from the Request's perspective.

The unhappy paths branch from `pending`:
- **Declined**: provider calls `decline!` (requires a `decline_reason`)
- **Expired**: system calls `expire!` (records `expired_at`) — presumably via a background job when `scheduled_at` passes without a response
