# Experiment: e02-happy-path
# App: app_delta | Model: opus | Run: 2

---

Here's the happy path for the main entity — the **Order** — walking through the full lifecycle from initial request to completion:

## Happy Path: Request → Order → Payment → Review

### 1. Client creates a Request
A **Client** submits a **Request** to a specific **Provider**, specifying `scheduled_at` and `duration_minutes`. The request starts in the **`pending`** state.

### 2. Provider accepts the Request
The Provider reviews the request and calls `accept!`. The request transitions to **`accepted`** and records `accepted_at`.

### 3. Order is created
An **Order** is created (linked to the accepted Request), capturing `scheduled_at`, `duration_minutes`, `amount_cents`, and `currency`. It starts in the **`pending`** state.

### 4. Order is confirmed
The order transitions to **`confirmed`** (e.g., after both parties acknowledge the details).

### 5. Payment is held
A **Payment** is created for the order (optionally linked to the client's default **Card**). It starts as `"pending"`, then `hold!` is called — moving it to `"held"` and recording `held_at`. This reserves the funds before the service begins.

### 6. Order starts
At the scheduled time, the order transitions to **`in_progress`** via `start!`, recording `started_at`.

### 7. Order completes
When the service is delivered, the order transitions to **`completed`** via `complete!`, recording `completed_at`.

### 8. Payment is charged
The held payment is finalized with `charge!`, moving it to `"charged"` and recording `charged_at`.

### 9. Reviews are left
Both the **Client** and the **Provider** can leave a **Review** on the completed order (rating 1–5, with optional body text). The system enforces that reviews can only be created on completed orders.

---

There's also a parallel flow via **Announcements**: a Client publishes an Announcement, Providers submit Responses, the Client selects a Response, and that leads into Order creation — but the core lifecycle above is the same once the Order exists.
