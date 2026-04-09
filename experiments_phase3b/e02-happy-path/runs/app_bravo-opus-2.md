# Experiment: e02-happy-path
# App: app_bravo | Model: opus | Run: 2

---

The main entity in this system is the **Order**. Here's the happy path, step by step:

### 1. Client creates a Request
- A **Client** submits a **Request** to a specific **Provider**, specifying `scheduled_at`, `duration_minutes`, location, and notes.
- The Request starts in the **`pending`** state.

### 2. Provider accepts the Request
- The **Provider** reviews and **accepts** the Request.
- Request transitions to **`accepted`**, `accepted_at` is recorded.
- Accepting a Request creates an **Order** (the Request `has_one :order`).

### 3. Order is created (pending)
- The Order is born in the **`pending`** state with `scheduled_at`, `duration_minutes`, `amount_cents`, `currency`, and a link back to the Request.
- A **Payment** is created for the Order in **`pending`** status.

### 4. Provider confirms the Order
- The Provider **confirms** the Order.
- Order transitions to **`confirmed`**.
- The Payment is **held** (`status: "held"`, `held_at` recorded) — funds are reserved on the Client's Card.

### 5. Provider starts the Order
- When the scheduled time arrives, the Provider **starts** the work.
- Order transitions to **`in_progress`**, `started_at` is recorded.

### 6. Provider completes the Order
- The Provider marks the Order as **complete**.
- Order transitions to **`completed`**, `completed_at` is recorded.
- The Payment is **charged** (`status: "charged"`, `charged_at` recorded).

### 7. Both parties leave Reviews
- Once the Order is `completed`, both the **Client** and **Provider** can submit a **Review** (rating 1-5, optional body).
- Each party can review the Order exactly once (uniqueness on `order_id` + `author_type` + `author_id`).

---

**State flow summary:**

```
Request:  pending → accepted
Order:    pending → confirmed → in_progress → completed
Payment:  pending → held → charged
```
