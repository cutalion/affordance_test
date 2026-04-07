# Experiment: 01-describe-system
# App: request | Model: sonnet | Run: 3

---

Here is a comprehensive description of this system:

---

## Domain

This is a **service marketplace / booking platform** — a backend Rails API that connects **clients** (customers who need a service) with **providers** (professionals who perform the service). Think of it as something like a on-demand service booking app (cleaning, tutoring, etc.), where a client requests a time slot from a provider, the provider fulfills the work, and payment is processed.

---

## Main Entities

| Entity | Description |
|---|---|
| **Client** | A customer with an email, name, API token, and stored payment cards. Places service requests. |
| **Provider** | A service professional with a rating, API token, and active/inactive status. Accepts and fulfills requests. |
| **Request** | The central entity — a scheduled service engagement between a client and provider, with a time, duration, location, price, and a lifecycle managed by a state machine. |
| **Payment** | Associated 1:1 with a Request. Tracks the monetary transaction through states: `pending → held → charged → refunded`. Includes a 10% platform fee. |
| **Card** | A client's payment method; one card can be marked as default. |
| **Review** | A post-fulfillment rating (1–5 stars) left by either a client or provider on a completed request. |

---

## Request Lifecycle (State Machine)

This app uses a **legacy/invitation-era** naming convention for states. The full state graph is:

```
created ──────────────────────────────→ accepted → started → fulfilled
   │         (provider accepts)              ↑          │
   │                                         │          ↓
   │         (provider creates direct) → created_accepted
   │
   ├──────────────────────────────────────────────────→ declined   (provider declines)
   ├──────────────────────────────────────────────────→ missed     (no response)
   ├──────────────────────────────────────────────────→ canceled   (client cancels)
   └──────────────────────────────────────────────────→ rejected   (provider rejects mid-flow)
```

Key nuance — the `created_accepted` state is unique to this app: a **provider can initiate a request on behalf of a client** (via `POST /api/requests/direct`) and it skips the normal acceptance step, landing directly in `created_accepted`.

---

## Typical Workflow

1. **Client books a service** — `POST /api/requests` — creates a `Request` in state `created`, notifies the provider, and creates a pending `Payment`.
2. **Provider responds** — `PATCH /api/requests/:id/accept` or `/decline` — moves the request to `accepted` or `declined`.
3. **Service begins** — `PATCH /api/requests/:id/start` — transitions to `started`, records `started_at`.
4. **Service completes** — `PATCH /api/requests/:id/fulfill` — transitions to `fulfilled`, records `completed_at`.
5. **Reviews submitted** — Both parties can post a review (rating 1–5) on the now-fulfilled request.
6. **At any point**, a client can **cancel** (with a reason) or a provider can **reject** (with a reason).

**Alternate (direct) flow:** A provider books directly for a client via `POST /api/requests/direct`, creating a `created_accepted` request, skipping the accept step.

---

## Meta-Context

This app is one of **two parallel Rails apps** in a research project (`affordance_test`). The experiment studies how **entity naming affects AI reasoning**: this `affordance_request` app uses legacy state names (`created`, `created_accepted`, `declined`, `fulfilled`, etc.), while the sibling `affordance_order` app uses cleaner names (`pending`, `confirmed`, `in_progress`, `completed`, etc.) for the structurally equivalent entity. The hypothesis being tested is whether AI models reason differently or make different mistakes depending on the vocabulary used for domain concepts.
