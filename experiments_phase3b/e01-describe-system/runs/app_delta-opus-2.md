# Experiment: e01-describe-system
# App: app_delta | Model: opus | Run: 2

---

This is a **service marketplace platform** — a two-sided marketplace connecting **Clients** (who need services) with **Providers** (who perform them). The domain is derived from Kidsout (likely a childcare/babysitting marketplace), generalized with neutral naming.

## Main Entities

- **Client** — a person seeking services. Has payment cards, notification preferences.
- **Provider** — a service professional with a specialization, rating, and active status.
- **Announcement** — a client broadcasts a need (draft → published → closed). Think "I need a babysitter Saturday evening."
- **Response** — a provider replies to an announcement with a proposed price and message. One response per provider per announcement.
- **Request** — a client directly asks a specific provider for a booking (pending → accepted/declined/expired).
- **Order** — the confirmed booking itself (pending → confirmed → in_progress → completed, or canceled/rejected). Tracks schedule, duration, amount, and links back to the originating request if any.
- **Payment** — financial transaction tied to an order. Supports hold → charge → refund flow.
- **Card** — stored payment cards for a client (with a default).
- **Review** — polymorphic (both client and provider can leave reviews on a completed order).
- **RecurringBooking** — a template for repeated sessions between a client and provider.

## Typical Workflows

1. **Direct booking**: Client sends a **Request** to a specific Provider → Provider accepts → an **Order** is created → Payment is held → Service happens → Order completed → Payment charged → Reviews exchanged.

2. **Announcement/bidding**: Client creates an **Announcement** describing the need → Publishes it → Providers submit **Responses** with proposed amounts → Client picks a provider → (presumably creates an Order from the chosen response) → same fulfillment flow.

3. **Recurring**: A **RecurringBooking** generates multiple Orders for repeated sessions.

The app exposes both an **API** (token-authenticated, for client/provider mobile apps) and an **Admin** interface (for back-office management).
