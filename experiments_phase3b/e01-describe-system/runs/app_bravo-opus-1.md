# Experiment: e01-describe-system
# App: app_bravo | Model: opus | Run: 1

---

This is a **service booking marketplace** — a platform where **clients** book time with **providers** (specialists/professionals). It's derived from a childcare/babysitting domain (Kidsout), abstracted into generic naming.

## Main Entities

- **Client** — a customer who books services. Has email, phone, notification preferences, and an API token for authentication.
- **Provider** — a service professional (e.g., babysitter). Has a specialization, rating, active status, and notification preferences.
- **Request** — a booking inquiry from a client to a provider. States: `pending → accepted / declined / expired`. Specifies schedule, duration, location, and notes.
- **Order** — a confirmed engagement. Can originate from a Request or be created directly. States: `pending → confirmed → in_progress → completed` (or `canceled`/`rejected`). Tracks amount, duration, and schedule.
- **Payment** — tied 1:1 to an Order. Lifecycle: `pending → held → charged → refunded`. Linked to a Card.
- **Card** — a client's saved payment method (brand, last four, expiry, token). One can be marked as default.
- **Review** — polymorphic by author (client or provider), tied to an Order. Has a rating and body. One review per author per order.
- **RecurringBooking** — a template for generating repeated requests for the same client/provider pair over multiple sessions.

## Typical Workflow

1. **Client registers** and saves a payment **Card**.
2. Client creates a **Request** to a specific Provider (date, duration, location).
3. Provider **accepts** (or declines/it expires). Accepting creates an **Order**.
4. The Order is **confirmed**, then **started**, then **completed**.
5. A **Payment** is held before the session, then charged upon completion (or refunded on cancellation).
6. After completion, both parties can leave a **Review**.

The app exposes two interfaces: an **API** (token-authenticated, for client/provider mobile apps) and a read-only **Admin** dashboard.
