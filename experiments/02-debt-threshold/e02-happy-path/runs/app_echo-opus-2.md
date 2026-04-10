# Experiment: e02-happy-path
# App: app_echo | Model: opus | Run: 2

---

The main entity in this system is the **Request** — a service booking between a Client and a Provider. Here's the happy path, step by step:

---

### 1. Client creates a Request (`pending`)

A **Client** sends a request to a specific **Provider**, specifying schedule, duration, location, notes, and price. The request is saved in `pending` state. The provider is notified via push/SMS/email.

> `Requests::CreateService` → Request state: **pending**

### 2. Provider accepts the Request (`accepted`)

The Provider reviews and accepts. On acceptance:
- The state transitions to **accepted**, and `accepted_at` is recorded.
- A **Payment** record is created (amount + 10% platform fee), initially in `pending` status.
- If the client has a default **Card** on file, the payment amount is **held** (pre-authorized) on that card.
- The client is notified.

> `Requests::AcceptService` → Request state: **accepted**, Payment status: **held**

### 3. Provider starts the work (`in_progress`)

When the scheduled time arrives, the Provider marks the request as started. `started_at` is recorded. The client is notified.

> `Requests::StartService` → Request state: **in_progress**

### 4. Provider completes the work (`completed`)

The Provider marks the request done. `completed_at` is recorded. If the payment was previously held, it is now **charged** (captured). Both client and provider are notified.

> `Requests::CompleteService` → Request state: **completed**, Payment status: **charged**

### 5. Both parties leave Reviews

After completion, either the client or provider (or both) can create a **Review** with a rating (1–5) and optional text body. Reviews are scoped per request and unique per author — each party can leave only one review.

---

**State machine summary for the happy path:**

```
pending → accepted → in_progress → completed
```

**Payment lifecycle in parallel:**

```
pending → held (at accept) → charged (at complete)
```
