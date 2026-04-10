# Experiment: e02-happy-path
# App: app_echo | Model: opus | Run: 3

---

The main entity in this system is the **Request** — a service booking between a Client and a Provider. Here's the happy path step by step:

---

### Step 1: Client creates a Request (`pending`)
A **Client** creates a request directed at a specific **Provider**, specifying the schedule, duration, location, amount, and optional notes. The provider receives a `request_created` notification.

`Requests::CreateService` → Request saved in `pending` state.

### Step 2: Provider accepts the Request (`pending` → `accepted`)
The **Provider** reviews and accepts. On acceptance:
- A **Payment** record is created (with a 10% platform fee calculated).
- If the client has a default **Card** on file, `PaymentGateway.hold` places a hold on the funds — the payment moves to `held` status.
- The client is notified (`request_accepted`).

`Requests::AcceptService#accept_invitation!` → Request moves to `accepted`, timestamps `accepted_at`.

### Step 3: Provider starts the work (`accepted` → `in_progress`)
When the scheduled time arrives, the **Provider** marks the request as started. The client is notified (`request_started`), and `started_at` is recorded.

`Requests::StartService` → Request moves to `in_progress`.

### Step 4: Provider completes the work (`in_progress` → `completed`)
After the service is delivered, the **Provider** marks it complete:
- If the payment was `held`, `PaymentGateway.charge` captures the funds — the payment moves to `charged`.
- Both client and provider receive `request_completed` notifications.
- `completed_at` is recorded.

`Requests::CompleteService` → Request moves to `completed`.

### Step 5: Review
After completion, either the **Client** or the **Provider** can leave a **Review** (rating + body text) on the request. Each party can only leave one review per request (enforced by a unique index on `[request_id, author_type, author_id]`).

---

**State machine summary (happy path):**
```
pending → accepted → in_progress → completed
```

**Money flow:**
```
hold (on accept) → charge (on complete)
```

There's also an alternative entry point via **Announcements** (client publishes an announcement, providers respond, client picks one), but the request lifecycle after acceptance follows the same `accepted → in_progress → completed` path.
