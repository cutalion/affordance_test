# Experiment: 01-describe-system
# App: request | Model: opus | Run: 3

---

Now I have a thorough understanding of the system. Here's a description:

---

## Domain

This is a **service marketplace platform** — a system where **clients** book **providers** for on-demand services (originating from a babysitting marketplace called "Kidsout"). The currency defaults to RUB, indicating a Russian market origin.

## Main Entities

1. **Client** — A customer who books services. Has an email, phone, API token for authentication, notification preferences, and payment cards on file.

2. **Provider** — A service professional who fulfills bookings. Has a rating (0–5), specialization, and an active/inactive status.

3. **Request** (the central entity) — A service booking that connects a Client to a Provider. It carries scheduling info (`scheduled_at`, `duration_minutes`, `location`), pricing (`amount_cents`, `currency`), and goes through a state machine lifecycle.

4. **Payment** — A 1:1 financial record attached to a Request. Tracks money through a `pending → held → charged` flow (with a possible `refunded` state). A 10% platform fee is calculated on creation.

5. **Card** — A stored payment method for a Client (token, last four digits, brand, expiry).

6. **Review** — A polymorphic review (from either a Client or a Provider) left on a completed Request, with a numeric rating and text body.

## Typical Workflow

1. **Creation** — A Client creates a Request for a specific Provider, choosing a time, duration, and location. A Payment record is automatically created alongside it (with a 10% fee). The Provider is notified.

2. **Acceptance** — The Provider **accepts** the Request (or **declines** / it gets **missed** if unresponsive). There's also a "direct" flow (`create_accepted`) where a Request is created already pre-accepted, skipping the acceptance step.

3. **Execution** — Once accepted, the Provider **starts** the service (recording `started_at`), then **fulfills** it (recording `completed_at`). The payment is held before the appointment and charged upon completion.

4. **Cancellation/Rejection** — At various stages, the Request can be **canceled** (by the client, requires a reason) or **rejected** (by the provider, requires a reason). Payments are refunded accordingly.

5. **Review** — After fulfillment, both parties can leave reviews.

## Meta-Purpose

This specific app (`affordance_request`) is one half of an **AI reasoning experiment**. A structurally identical sister app (`affordance_order`) exists with the entity named "Order" and a cleaner state machine (`pending → confirmed → in_progress → completed`). The experiment tests whether the legacy naming ("Request") and its messier states (`created`, `created_accepted`, `declined`, `missed`, etc.) cause AI agents to reason differently about the same underlying domain — essentially probing how **naming affordances** affect AI comprehension.
