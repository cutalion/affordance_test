# Experiment: 07-happy-path
# App: request | Model: opus | Run: 1

---

The main entity is **Request** — a service booking between a Client and a Provider. Here's the happy path:

### 1. **Created** (initial state)
A **Client** creates a Request by choosing a Provider and specifying schedule, duration, location, notes, and price. A **Payment** record is automatically created in `pending` status with a 10% platform fee. The Provider gets a notification.

### 2. **Accepted**
The **Provider** reviews and accepts the request. The Client is notified. (The state transitions `created → accepted`.)

### 3. **Started**
When it's time for the service, the **Provider** starts the request. `started_at` is recorded. The Client is notified. (Transition: `accepted → started`.)

### 4. **Fulfilled**
The **Provider** marks the request as complete. `completed_at` is recorded. If the payment was previously held (status `held`), it is now **charged** via the PaymentGateway. Both Client and Provider are notified. (Transition: `started → fulfilled`.)

### Payment lifecycle alongside the Request:
- **pending** — created with the Request
- **held** — funds are held on the Client's card (triggered externally, likely before the scheduled time — the `pending_holds` scope targets requests within 24 hours)
- **charged** — captured upon fulfillment

So the happy path is: **created → accepted → started → fulfilled**, with the payment moving **pending → held → charged** in parallel.
