# Experiment: e01-describe-system
# App: app_echo | Model: opus | Run: 3

---

Here's what this system does:

## Domain

This is a **services marketplace** — a Rails API application connecting **clients** who need services with **providers** who perform them. The currency defaults to RUB, suggesting a Russian market. Think of it as a platform for booking appointments with professionals (tutors, cleaners, repair workers, etc.).

## Main Entities

- **Client** — a person who needs a service. Has saved payment cards and notification preferences.
- **Provider** — a professional who fulfills service requests. Has a specialization, rating, and active/inactive status.
- **Announcement** — a client-created "job posting" (draft → published → closed). Describes what the client needs, with budget, location, scheduled time, and duration.
- **Request** — the core entity. Represents a booking of a specific provider by a client, with a price, schedule, and location. Can optionally be linked to an announcement.
- **Payment** — tied 1:1 to a request. Follows a hold → charge → (optional refund) lifecycle using the client's saved card.
- **Card** — a client's saved payment card (tokenized, stores last four digits). One card can be marked as default.
- **Review** — polymorphic (either client or provider can author). Left after a request is completed. Rating + text body.

## Typical Workflow

1. **Client posts an announcement** (or contacts a provider directly) describing what they need.
2. **Client creates a request** to a specific provider — specifying schedule, duration, price, and location. The provider is notified.
3. **Provider accepts or declines**. On accept, a payment hold is placed on the client's default card.
4. **Provider starts** the job (accepted → in_progress).
5. **Provider completes** the job — the held payment is charged automatically.
6. Both parties can leave **reviews** with a rating.

Alternative flows: the client can **cancel** (pending/accepted states), the provider can **reject** (accepted/in_progress), and cancellation/rejection triggers a **refund** if payment was already held.

The app exposes two API surfaces: a token-authenticated **client/provider API** (`/api`) and a basic-auth **admin panel** (`/admin`) for read-only oversight.
