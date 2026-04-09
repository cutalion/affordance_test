# Experiment: e05-recurring-bookings
# App: app_delta | Model: opus | Run: 3
# Branch: debt_experiment/e05-recurring-bookings/app_delta/opus/run-3

---

## Claude Output

Good — I now have a clear picture. The DB already has `recurring_bookings` table and `orders.recurring_booking_id` FK, but no model, service, controller, or tests exist for recurring bookings. Here's my design:

## Recurring Weekly Bookings — Design

**Concept:** A client books 5 weekly sessions with the same provider. This creates a `RecurringBooking` parent record and 5 `Order` records, each scheduled 1 week apart, each with its own `Payment`.

**Components:**

1. **`RecurringBooking` model** — belongs_to client & provider; has_many orders. Validates session_count (fixed at 5), amount, duration, first_scheduled_at.

2. **`RecurringBookings::CreateService`** — Accepts client, provider, and params (first_scheduled_at, duration_minutes, location, notes, amount_cents, currency). In a transaction: creates the RecurringBooking, then 5 orders (weeks 0-4) each with a payment. Notifies provider once about the full series.

3. **`Order` model** — Add `belongs_to :recurring_booking, optional: true` (FK already in DB).

4. **`Client` / `Provider` models** — Add `has_many :recurring_bookings`.

5. **API endpoint** — `POST /api/recurring_bookings` (client-only). Returns the recurring booking with all 5 orders.

6. **`GET /api/recurring_bookings`** — List recurring bookings for current user (client sees theirs, provider sees theirs).

7. **`GET /api/recurring_bookings/:id`** — Show detail with nested orders.

8. **Admin** — `GET /admin/recurring_bookings` index and show.

9. **Specs** — Model spec, service spec, factory.

This follows existing patterns exactly (service objects, notification logging, controller JSON helpers, factories with traits).

Does this design look right? Should I proceed with implementation?

---

## Git Diff

```diff

```
