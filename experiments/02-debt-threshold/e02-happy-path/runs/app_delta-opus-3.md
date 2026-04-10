# Experiment: e02-happy-path
# App: app_delta | Model: opus | Run: 3

---

The main entity in this system is the **Order**. Here's the happy path, step by step:

---

### Step 1: Client creates a Request
A **Client** sends a booking request to a specific **Provider**, specifying a schedule, duration, location, and notes.
- `Requests::CreateService` creates a `Request` in **pending** state.
- The Provider is notified (`request_created`).

### Step 2: Provider accepts the Request
The Provider reviews the pending Request and accepts it.
- `Requests::AcceptService` transitions the Request from **pending** → **accepted**.
- Within the same transaction, an **Order** is automatically created (via `Orders::CreateService`) linked to that Request, with a hardcoded amount of 350,000 kopecks (3,500 RUB).
- A **Payment** record is also created in **pending** status, with a 10% platform fee.
- The Provider is notified of the new order; the Client is notified the request was accepted.

### Step 3: Provider confirms the Order
The Provider confirms they're ready for the scheduled appointment.
- `Orders::ConfirmService` transitions the Order from **pending** → **confirmed**.
- The Client is notified (`order_confirmed`).

### Step 4: Provider starts the Order
When the scheduled time arrives, the Provider marks the order as in progress.
- `Orders::StartService` transitions the Order from **confirmed** → **in_progress**.
- `started_at` is timestamped.
- The Client is notified (`order_started`).

### Step 5: Provider completes the Order
After the service is delivered, the Provider marks it complete.
- `Orders::CompleteService` transitions the Order from **in_progress** → **completed**.
- `completed_at` is timestamped.
- If a payment was held, `PaymentGateway.charge` finalizes the payment.
- Both Client and Provider are notified (`order_completed`).

### Step 6: Review (optional)
After completion, the Client (or Provider) can leave a **Review** on the Order.

---

**State machine summary:**

```
Request:  pending → accepted
Order:    pending → confirmed → in_progress → completed
Payment:  pending → [held] → charged
```

This is a two-sided marketplace where Clients book Providers through requests, which convert into paid orders that progress through confirmation, execution, and completion.
