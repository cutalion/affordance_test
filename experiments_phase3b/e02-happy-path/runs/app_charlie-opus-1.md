# Experiment: e02-happy-path
# App: app_charlie | Model: opus | Run: 1

---

The main entity is **Request**. Here's its happy path, step by step:

### 1. **Pending** (initial state)
A **Client** creates a Request for a **Provider**, specifying `scheduled_at`, `duration_minutes`, `amount_cents`, and `currency`. A **Payment** is created alongside it in `pending` status.

### 2. **Accepted**
The Provider reviews and **accepts** the request. `accepted_at` is recorded. At this point, the Payment can be **held** (funds reserved on the client's Card).

### 3. **In Progress**
At the scheduled time, the request **starts**. `started_at` is recorded. The provider is now delivering the service.

### 4. **Completed**
The provider finishes and the request is **completed**. `completed_at` is recorded. The held Payment is **charged** (funds captured).

### 5. **Reviewed**
After completion, both the Client and Provider can leave **Reviews** (rating 1-5). Each party can review once per request — the review validates that the request is in `completed` state.

---

**Payment flow in parallel:** `pending` → `held` (on accept) → `charged` (on complete).

**Unhappy paths branch off at:**
- Pending: `decline` (provider refuses), `expire` (no response), `cancel` (client withdraws)
- Accepted: `cancel` (client withdraws), `reject` (provider backs out)
- In Progress: `reject` (provider backs out — payment would be refunded)
