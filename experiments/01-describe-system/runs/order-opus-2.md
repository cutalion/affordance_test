# Experiment: 01-describe-system
# App: order | Model: opus | Run: 2

---

Here's a description of the system:

## Domain

This is a **service booking and order management platform** — a two-sided marketplace where **clients** book time-based services from **providers** (think of something like a cleaning service, tutoring, beauty appointments, etc.). The default currency is RUB (Russian rubles), suggesting a Russian market focus.

## Main Entities

- **Client** — A customer who books services. Has an email, name, phone, API token for authentication, and notification preferences (push/SMS/email). Can have multiple payment cards.
- **Provider** — A service professional who fulfills orders. Has a rating (0–5), specialization, and an active/inactive status. Also authenticates via API token.
- **Order** — The core entity. Represents a booking of a provider by a client at a scheduled time, for a given duration, at a specific location. Tracks price (`amount_cents` + `currency`), notes, and has a state machine lifecycle.
- **Card** — A stored payment card belonging to a client (tokenized, with last four digits, brand: Visa/Mastercard/Amex/Mir). One card can be marked as the default.
- **Payment** — Tracks the financial lifecycle of an order. Has its own status flow: `pending → held → charged → refunded`. Can include a fee component (`fee_cents`).
- **Review** — A polymorphic rating (1–5 with optional text) left by either a client or a provider on a completed order. Each party can leave one review per order.

## Typical Workflow

1. **Registration** — A client or provider registers and receives an API token.
2. **Card setup** — The client adds one or more payment cards and sets a default.
3. **Order creation** — The client creates an order, specifying a provider, scheduled time, duration, location, and amount.
4. **Order lifecycle** (state machine):
   - **Pending** → **Confirmed** (provider confirms) → **In Progress** (provider starts the service) → **Completed** (provider marks it done)
   - Alternatively, an order can be **Canceled** (from pending or confirmed) with a reason, or **Rejected** (from confirmed or in-progress) with a reason.
5. **Payment flow** — A payment is created for the order. Before the service, funds are **held**; after completion, they are **charged**; if canceled, they can be **refunded**.
6. **Review** — After an order is completed, both the client and provider can leave a review with a 1–5 star rating.

The system exposes two interfaces: a **JSON API** (for client/provider mobile or web apps) and a read-only **Admin panel** (dashboard with views of orders, clients, providers, and payments).
