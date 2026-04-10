# Experiment: 07-happy-path
# App: order | Model: sonnet | Run: 2

---

Here's the happy path for an **Order** (the main entity), step by step:

---

**1. Client creates an Order** (`Orders::CreateService`)
- Client selects a provider, time, duration, and location
- An `Order` is created in `pending` state
- A `Payment` record is created alongside it (status: `pending`, with a 10% platform fee)
- Provider is notified: `:order_created`

**2. Payment is held** (`PaymentHoldJob`)
- A background job runs periodically, looking for `pending`/`confirmed` orders scheduled within the next 24 hours
- For orders with a `pending` payment and a card on file, `PaymentGateway.hold` is called — funds are reserved but not charged

**3. Provider confirms the Order** (`Orders::ConfirmService`)
- Provider calls confirm; state transitions `pending → confirmed`
- Client is notified: `:order_confirmed`

**4. Provider starts the Order** (`Orders::StartService`)
- At service time, provider marks it started; state transitions `confirmed → in_progress`
- `started_at` is recorded
- Client is notified: `:order_started`

**5. Provider completes the Order** (`Orders::CompleteService`)
- Provider marks it complete; state transitions `in_progress → completed`
- `completed_at` is recorded
- If payment is `held`, `PaymentGateway.charge` is called — funds are captured
- Both client and provider are notified: `:order_completed`

**6. Reviews are requested** (`ReviewReminderJob`)
- 24–48 hours after completion, a job checks for orders missing reviews
- Sends `:review_reminder` to any party (client or provider) who hasn't left one yet

---

State machine summary: `pending → confirmed → in_progress → completed`
