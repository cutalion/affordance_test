# Experiment: e02-happy-path
# App: app_charlie | Model: opus | Run: 3

---

Here's the happy path for the main entity — a **Request** — step by step:

---

## Happy Path of a Request

### 1. Client creates a Request (`pending`)
A **Client** submits a request to a specific **Provider**, specifying schedule, duration, location, notes, and price. The request is saved in `pending` state. The provider receives a `request_created` notification.

**State:** `pending` | **Payment:** none yet

### 2. Provider accepts the Request (`accepted`)
The provider reviews and accepts. This does two things in a single transaction:
- Transitions the request to `accepted` (records `accepted_at`)
- Creates a **Payment** record (`pending` status) with a 10% platform fee

If the client has a default **Card** on file, the payment gateway immediately places a **hold** on the card (payment status becomes `held`). The client is notified.

**State:** `accepted` | **Payment:** `pending` → `held`

### 3. Provider starts the work (`in_progress`)
When the scheduled time arrives, the provider marks the request as started. This records `started_at` and notifies the client.

**State:** `in_progress` | **Payment:** `held`

### 4. Provider completes the work (`completed`)
The provider marks the request as done. This records `completed_at`. If the payment was in `held` status, the gateway **charges** the card (payment status becomes `charged`). Both client and provider are notified.

**State:** `completed` | **Payment:** `held` → `charged`

### 5. Both parties leave Reviews
Once the request is `completed`, both the client and provider can submit a **Review** (rating 1-5 plus optional text). Each party can only review once per request.

---

### State machine summary

```
pending → accepted → in_progress → completed
```

### Payment lifecycle

```
(created at accept) pending → held → charged
```
