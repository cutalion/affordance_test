# Experiment: e02-happy-path
# App: app_alpha | Model: opus | Run: 3

---

The main entity is **Request**. Here's the happy path:

## Happy Path: Request lifecycle

**1. Client creates a Request**
- A `Client` calls `POST /api/requests` with `provider_id`, `scheduled_at`, `duration_minutes`, and optionally `location` and `notes`.
- `Requests::CreateService` builds the Request, which starts in the **`pending`** state (the AASM initial state).
- The provider is notified via `NotificationService` (`:request_created`).

**2. Provider accepts the Request**
- The assigned `Provider` calls `POST /api/requests/:id/accept`.
- `Requests::AcceptService` verifies the provider owns this request, then triggers the `accept!` AASM event.
- State transitions: **`pending` → `accepted`**.
- `accepted_at` is stamped with the current time.
- The client is notified (`:request_accepted`).

**3. The service is delivered**
- The request has a `scheduled_at` datetime and `duration_minutes` — the provider shows up at the `location` and performs the service.

That's the happy path: **pending → accepted → service delivered**.

### Unhappy paths (for context)
- **Declined**: Provider calls `decline` with a `reason` → state goes to `declined`.
- **Expired**: If the provider never responds, the `expire` event moves it to `expired` (with an `expired_at` timestamp). There's no automated expiration job visible in the code — this would be triggered externally or via a scheduled task.
