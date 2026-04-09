# Experiment: e02-happy-path
# App: app_echo | Model: opus | Run: 3

---

The main entity is **Request** — a service booking between a Client and a Provider. Here's the happy path:

### Step 1: `pending` — Client creates a Request
A client picks a provider and submits a request with a scheduled time, duration, location, and agreed price (`amount_cents`). The request starts in the **pending** state. A **Payment** record is also created (status: `pending`).

### Step 2: `accepted` — Provider accepts
The provider reviews the incoming request and calls `accept`. The state moves to **accepted** and `accepted_at` is timestamped. At this point the payment is typically put on **hold** (`held`), reserving funds on the client's card.

### Step 3: `in_progress` — Provider starts the service
When the scheduled time arrives, the provider calls `start`. The state moves to **in_progress** and `started_at` is recorded. The service is now being delivered.

### Step 4: `completed` — Provider completes the service
Once the work is done, the provider calls `complete`. The state moves to **completed**, `completed_at` is timestamped, and the held payment is **charged**.

### Step 5: Review
After completion, either party can leave a **Review** on the request.

---

**Alternate (non-happy) paths:**
- **declined** — provider declines the pending request (with reason)
- **expired** — pending request times out with no response
- **canceled** — client cancels while pending or accepted (with reason)
- **rejected** — provider rejects after accepting or during service (with reason)

In those cases the payment would be **refunded** rather than charged.
