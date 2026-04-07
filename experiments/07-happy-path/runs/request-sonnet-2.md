# Experiment: 07-happy-path
# App: request | Model: sonnet | Run: 2

---

Here's the happy path for a **Request** in this system:

---

**1. `created` (initial)**
A client creates a Request with a provider, scheduled time, duration, and amount. The request exists but hasn't been acted on yet.

**2. `accepted`**
The provider accepts the request via the `accept` event. This signals they're committed to showing up.

**3. `started`**
The session begins — the `start` event fires, recording `started_at` as the current timestamp. (Can also transition from the orphaned `created_accepted` state.)

**4. `fulfilled`**
The session completes successfully — the `fulfill` event fires, recording `completed_at`. This is the terminal happy-path state.

---

**Off-ramp states** (not happy path):
- `declined` — provider says no at `created`
- `missed` — provider no-showed at `created`
- `canceled` — client or system canceled before it started
- `rejected` — aborted after acceptance or even mid-session

**Note on `created_accepted`:** This state exists but has no transition leading *into* it from the defined events — it's a legacy artifact from Kidsout's invitation-era design. It can transition *out* to `started` or `canceled`, suggesting it was once a meaningful intermediate state (possibly a two-phase acceptance) that was never cleaned up.
