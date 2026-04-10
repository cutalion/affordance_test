# Experiment: 01-describe-system
# App: order | Model: sonnet | Run: 4

---

Here is a comprehensive description of the system:

---

## System Overview

**`affordance_order`** is a Ruby on Rails API backend for a **service marketplace** — a platform that connects **clients** (customers) with **providers** (service professionals, e.g. home services, personal care, or similar on-demand specializations). The currency defaults to RUB, suggesting it is likely a Russian-market application.

---

## Domain

The domain is **on-demand service booking**: clients book time-based appointments with providers, with integrated payment handling and post-service reviews.

---

## Main Entities

| Entity | Role |
|---|---|
| **Client** | The customer who books services. Has an email, phone, API token for authentication, saved payment cards, and configurable notification preferences. |
| **Provider** | The service professional. Has an email, phone, specialization, a rating (0–5), an active flag, and notification preferences. |
| **Order** | The core booking record. Links a client to a provider for a scheduled appointment with a specific duration, location, price (in cents), and optional notes. |
| **Payment** | One-to-one with an Order. Tracks the financial transaction through hold → charge → refund states, with a 10% platform fee calculated at creation. |
| **Card** | A saved payment card (tokenized) belonging to a client, supporting Visa, Mastercard, Amex, and Mir brands. One card can be set as the default. |
| **Review** | A post-completion rating (1–5) with an optional text body. Both the client *and* the provider can leave a review for the same order, but only after it is completed. |

---

## Order Lifecycle (State Machine)

```
[pending] ──confirm──▶ [confirmed] ──start──▶ [in_progress] ──complete──▶ [completed]
    │                       │                       │
  cancel                 cancel                  reject
    │                       │                       │
    ▼                       ▼                       ▼
[canceled]             [canceled]              [rejected]
```

| Transition | Actor | Side Effects |
|---|---|---|
| **Create** | Client | Creates the order + a `pending` payment; notifies the provider. |
| **Confirm** | Provider | Moves order to `confirmed`; notifies the client. |
| **Start** | Provider | Moves to `in_progress`; records `started_at`. |
| **Complete** | Provider | Moves to `completed`; records `completed_at`; **charges** the held payment; notifies both parties. |
| **Cancel** | Client | Cancels from `pending` or `confirmed` (requires a reason); **refunds** any held/charged payment; notifies the provider. |
| **Reject** | Provider | Rejects from `confirmed` or `in_progress` (requires a reason). |

---

## Payment Flow

Payments go through a two-phase process managed by the `PaymentGateway` service:
1. **Hold** — funds are reserved on the client's default card (triggered pre-service, e.g. automatically for orders scheduled within 24 hours via the `pending_holds` scope).
2. **Charge** — funds are captured upon order completion.
3. **Refund** — triggered if the client cancels after a hold/charge has occurred.

---

## Notifications

The `NotificationService` dispatches event-driven notifications (order created, confirmed, completed, canceled) to clients and providers via three configurable channels: **push**, **SMS**, and **email** (email is dispatched via `OrderMailer` + ActiveJob). Each user controls their preferences independently.

---

## API

The system exposes a JSON REST API (under `api/`) with controllers for all entities: `clients`, `providers`, `orders`, `payments`, `cards`, and `reviews`. Authentication is token-based (each client and provider has a unique `api_token`). An `admin/` namespace also exists for back-office access.
