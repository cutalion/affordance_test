# Experiment: 07-happy-path
# App: order | Model: sonnet | Run: 3

---

The main entity is **Order**. Here's the happy path:

**1. Creation — `pending`**
A client creates an order by specifying a provider, scheduled time, duration, amount, and optional location/notes. The order starts in `pending` state. A `Payment` record is also created (status: `pending`).

**2. Provider confirms — `confirmed`**
The provider reviews and confirms the order (`order.confirm!`). At this point, payment is typically held/authorized against the client's card (`payment.held_at` set).

**3. Service starts — `in_progress`**
When the scheduled time arrives and the provider begins work, the order transitions to `in_progress` (`order.start!`). `started_at` is recorded automatically.

**4. Service completes — `completed`**
The provider marks the work done (`order.complete!`). `completed_at` is recorded. Payment is charged (`payment.charged_at` set, status moves to charged).

**5. Reviews submitted**
After completion, both the client and provider can leave a review (rating + optional body) on the order. The unique index on `(order_id, author_type, author_id)` ensures one review per party.

---

State chain: `pending → confirmed → in_progress → completed`

The off-ramps are `cancel` (from `pending` or `confirmed`, requires `cancel_reason`) and `reject` (from `confirmed` or `in_progress`, requires `reject_reason`).
