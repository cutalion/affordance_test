# Experiment: 07-happy-path
# App: request_clean | Model: opus | Run: 2

---

The main entity is **Request**. Here's the happy path, step by step:

### 1. **`pending`** — Client creates a request
A client submits a request for a service, specifying a provider, scheduled time, duration, and amount. The request starts in the `pending` state.

### 2. **`confirmed`** — Provider confirms
The provider reviews the pending request and confirms it (`confirm` event). This signals they accept the job and will show up.

### 3. **`in_progress`** — Service begins
When the scheduled time arrives, the request transitions to `in_progress` (`start` event). The `started_at` timestamp is recorded.

### 4. **`completed`** — Service finishes
Once the service is delivered, the request moves to `completed` (`complete` event). The `completed_at` timestamp is recorded.

### 5. **Payment is charged**
The associated Payment (created with status `pending`) follows its own lifecycle alongside the request:
- **`held`** — funds are held on the client's card before or at confirmation
- **`charged`** — once the request completes, the held funds are captured

### 6. **Reviews are left**
After completion, both the client and provider can leave a review (validated by `request_must_be_completed`). Each side can review once per request.

---

**Unhappy paths** branch off at steps 1-2 (`cancel` from pending/confirmed) or step 3 (`reject` from confirmed/in_progress), which would lead to a payment `refund!` instead of a charge.
