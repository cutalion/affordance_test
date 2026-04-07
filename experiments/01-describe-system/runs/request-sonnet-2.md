# Experiment: 01-describe-system
# App: request | Model: sonnet | Run: 2

---

Here is a comprehensive description of this system:

---

## Domain

This is a **service marketplace / booking platform** — specifically a Rails 8 JSON API where **Clients** book service appointments with **Providers**. Think of it as a platform for on-demand professional services (e.g., a cleaning, repair, or personal care booking app). The currency defaults to **RUB**, suggesting a Russian-market origin.

---

## Main Entities

| Entity | Role |
|---|---|
| **Client** | The consumer who books a service. Has an API token, email, phone, and notification preferences. |
| **Provider** | The service professional who fulfills requests. Has a rating, specialization, active flag, and API token. |
| **Request** | The central entity — a service booking between a Client and a Provider. Has a scheduled time, duration, location, notes, and price. |
| **Payment** | Associated 1-to-1 with a Request. Tracks amount, fee (10%), currency, and lifecycle (pending → held → charged/refunded). |
| **Card** | A saved payment card belonging to a Client (brand, last four digits, expiry, token). |
| **Review** | A polymorphic rating + comment left on a Request, authored by either a Client or Provider. |

---

## Request Lifecycle (State Machine)

This app uses **legacy "invitation-era" states** managed by the AASM gem:

```
            ┌─────────────────────────────────────────┐
            │                                         │
         created ──────────────────────────────► declined
            │                                         
            │                                    missed
            │
            ├──[client cancels]──────────────► canceled
            │
            ├──[provider accepts]──────────► accepted ──[cancel]──► canceled
            │                                  │
            │                                  │──[start]──► started ──[fulfill]──► fulfilled
            │                                  │                │
            │                                  │                └──[reject]──► rejected
            │                                  └──[reject]──► rejected
            │
            └──[provider creates direct]──► created_accepted
                                                │
                                                ├──[cancel]──► canceled
                                                ├──[start]──► started
                                                └──[reject]──► rejected
```

Key states:
- **`created`** — Client submitted a booking request; awaiting provider response
- **`created_accepted`** — Provider created it directly (pre-accepted, skipping the invitation step)
- **`accepted`** — Provider accepted the client's request
- **`started`** — Service is underway (records `started_at`)
- **`fulfilled`** — Service completed (records `completed_at`); triggers payment charge
- **`declined`** / **`missed`** / **`canceled`** / **`rejected`** — Terminal negative states

---

## Typical Workflow

**Standard client-initiated flow:**
1. **Client** calls `POST /api/requests` → creates a Request in `created` state + a pending Payment
2. **Provider** receives a notification and calls `POST /api/requests/:id/accept` → state → `accepted`
3. At appointment time, **Provider** calls `POST /api/requests/:id/start` → state → `started`
4. After completion, **Provider** calls `POST /api/requests/:id/fulfill` → state → `fulfilled`; the held payment is charged
5. Both parties can leave **Reviews**

**Provider-initiated ("direct") flow:**
1. **Provider** calls `POST /api/requests/direct` with a specific `client_id` → creates a Request in `created_accepted` state (bypasses the invitation/acceptance step)
2. Service starts and fulfills as above

**Cancellation/rejection** can happen at various stages — clients cancel, providers decline early or reject later.

---

## Architecture

- **Rails 8.1 API mode** (JSON) with a separate **admin HTML section** (ERB, HTTP Basic Auth)
- **Service objects** (`Requests::CreateService`, `AcceptService`, `FulfillService`, etc.) encapsulate each state transition
- **`NotificationService`** and **`PaymentGateway`** are adapter-style services called after state changes
- Authentication is token-based (`api_token` on Client/Provider)
- Pagination via a `Paginatable` concern

---

## Context: Why This App Exists

This is one of **two parallel apps** in an AI research experiment (`affordance_test`). The companion app (`affordance_order`) is structurally identical but uses the entity name **Order** with cleaner state names (`pending`, `confirmed`, `in_progress`, `completed`…). The experiment studies whether the **name of the central entity** ("Request" vs. "Order") affects how an AI model reasons about and modifies the codebase — a form of *linguistic affordance* testing.
