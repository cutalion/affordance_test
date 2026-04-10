# Experiment: e02-happy-path
# App: app_delta | Model: opus | Run: 2

---

The main entity in this system is the **Order**. Here's the happy path, step by step:

---

### Step 1: Client creates a Request
A **Client** submits a request to a specific **Provider**, specifying a schedule time, duration, location, and notes. The request is created in `pending` state. The provider receives a `request_created` notification.

*Service:* `Requests::CreateService`
*State:* Request → `pending`

### Step 2: Provider accepts the Request
The provider reviews the pending request and accepts it. This does two things in a single transaction:
- Transitions the request from `pending` → `accepted`
- Automatically creates an **Order** (with a hardcoded price of 3,500 RUB) linked to that request

The client is notified that the request was accepted.

*Service:* `Requests::AcceptService`
*State:* Request → `accepted`, Order → `pending`

### Step 3: Order and Payment are created
As part of step 2, `Orders::CreateService` creates the order and also creates a **Payment** record with `pending` status and a 10% platform fee. The provider is notified of the new order.

*State:* Order → `pending`, Payment → `pending`

### Step 4: Provider confirms the Order
The provider confirms they will fulfill the order. The order transitions from `pending` → `confirmed`. The client is notified.

*Service:* `Orders::ConfirmService`
*State:* Order → `confirmed`

### Step 5: Provider starts the Order
When the scheduled time arrives, the provider marks the order as started. It transitions from `confirmed` → `in_progress`, and `started_at` is recorded. The client is notified.

*Service:* `Orders::StartService`
*State:* Order → `in_progress`

### Step 6: Provider completes the Order
When work is done, the provider completes the order. It transitions from `in_progress` → `completed`, and `completed_at` is recorded. If the payment was in `held` status, `PaymentGateway.charge` is called to finalize the charge. Both client and provider are notified.

*Service:* `Orders::CompleteService`
*State:* Order → `completed`, Payment → `charged`

### Step 7: Client leaves a Review
After completion, the client can leave a review on the order (the `Order` model `has_many :reviews`).

---

**Summary of the happy path state machine:**

```
Request:  pending → accepted
Order:    pending → confirmed → in_progress → completed
Payment:  pending → held → charged
```
