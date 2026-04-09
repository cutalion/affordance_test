# Experiment: e02-happy-path
# App: app_delta | Model: opus | Run: 3

---

The main entity in this system is the **Order**. Here's the happy path, step by step:

## Happy Path: Order Lifecycle

### 1. Client creates a Request
A **Client** sends a **Request** to a specific **Provider**, specifying `scheduled_at` and `duration_minutes`. The Request starts in `pending` state.

### 2. Provider accepts the Request
The Provider reviews and **accepts** the Request (`pending → accepted`), which records `accepted_at`. This leads to an **Order** being created, linked to the Request.

### 3. Order is created (pending)
The **Order** is created in `pending` state, tied to the Client, Provider, and optionally the originating Request. It has `scheduled_at`, `duration_minutes`, `amount_cents`, and `currency`.

### 4. Order is confirmed
The Provider (or system) **confirms** the Order (`pending → confirmed`).

### 5. Payment is held
A **Payment** is created for the Order (using the Client's **Card**). The payment moves from `pending` to `held` — funds are reserved before the service begins.

### 6. Order starts
At the scheduled time, the Order **starts** (`confirmed → in_progress`), recording `started_at`.

### 7. Order completes
When the service is done, the Order **completes** (`in_progress → completed`), recording `completed_at`.

### 8. Payment is charged
The held Payment is **charged** (`held → charged`), finalizing the money transfer.

### 9. Reviews are left
Both the Client and Provider can leave **Reviews** on the completed Order (rating 1–5 with optional body). The system enforces that the order must be completed before reviewing.

---

There's also an alternative acquisition flow via **Announcements**: a Client publishes an Announcement, Providers submit **Responses**, the Client selects a Response, and that leads to an Order. But the core Order lifecycle (confirm → start → complete → pay → review) is the same either way.
