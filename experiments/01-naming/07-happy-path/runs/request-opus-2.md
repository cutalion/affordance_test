# Experiment: 07-happy-path
# App: request | Model: opus | Run: 2

---

The main entity is **Request** — a service booking between a client and a provider. Here's the happy path:

### 1. **Created** (initial state)
A client creates a request specifying a provider, scheduled time, duration, location, and amount. A `Payment` record is created alongside it in `pending` status.

### 2. **Accepted**
The provider reviews and accepts the request (`created → accepted`).

### 3. Payment Hold
As the scheduled time approaches (within 24 hours — see `Payment.pending_holds`), the payment is held against the client's card (`pending → held`).

### 4. **Started**
At the scheduled time, the service session begins (`accepted → started`). The `started_at` timestamp is recorded.

### 5. **Fulfilled**
The provider completes the service (`started → fulfilled`). The `completed_at` timestamp is recorded.

### 6. Payment Charged
After fulfillment, the held payment is charged (`held → charged`).

### 7. **Review**
The client (and/or provider) can leave a review on the fulfilled request.

---

**Unhappy paths branch off at various points:** the provider can **decline** the request, the request can be **missed** (no response), either party can **cancel** before it starts, or the request can be **rejected** even after acceptance/start — in those cases the payment would be refunded.
