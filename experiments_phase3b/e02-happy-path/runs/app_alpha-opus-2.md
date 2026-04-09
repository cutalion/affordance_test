# Experiment: e02-happy-path
# App: app_alpha | Model: opus | Run: 2

---

The main entity is **Request**. Here's the happy path, step by step:

### 1. Client creates a Request
- A **Client** picks a **Provider** and submits a request with `scheduled_at`, `duration_minutes`, and optionally `location`/`notes`.
- `Requests::CreateService` builds the Request record (state defaults to **`pending`**) and saves it.
- The **Provider** is notified (`:request_created`).

### 2. Provider accepts the Request
- The assigned **Provider** calls the accept endpoint.
- `Requests::AcceptService` verifies the provider owns the request, then triggers the AASM `accept!` transition: **`pending` → `accepted`**.
- `accepted_at` is stamped with the current time.
- The **Client** is notified (`:request_accepted`).

### That's it — two steps.

The **`pending → accepted`** transition is the happy path. The alternative (non-happy) paths are:

- **Decline**: Provider declines with a reason → **`pending` → `declined`**
- **Expire**: A pending request passes its window → **`pending` → `expired`** (with `expired_at` timestamp)

All three terminal states (`accepted`, `declined`, `expired`) are reachable only from `pending` — there are no further transitions after that.
