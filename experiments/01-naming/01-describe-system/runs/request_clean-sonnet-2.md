# Experiment: 01-describe-system
# App: request_clean | Model: sonnet | Run: 2

---

This is a **service marketplace / booking platform** (appears to be derived from the Kidsout domain — likely childcare services).

## Domain

A two-sided marketplace where **clients** book services from **providers**.

## Main Entities

| Entity | Role |
|--------|------|
| **Client** | Consumer who books services; has payment cards, notification preferences |
| **Provider** | Service professional with a rating and specialization |
| **Request** | A booking/appointment — the core transactional entity |
| **Payment** | Attached 1:1 to each Request; tracks hold/charge/refund lifecycle |
| **Card** | Stored payment method belonging to a Client |
| **Review** | Post-service rating left by either party on a Request |

## Typical Workflow

```
Client creates Request (pending)
    → Payment record created (pending), 10% fee calculated
    → Provider notified

Provider confirms Request (confirmed)
    → Payment hold placed (PaymentHoldJob)

Provider starts Request (in_progress)
    → started_at timestamp recorded

Provider completes Request (completed)
    → completed_at recorded
    → Payment charged
    → Review reminder sent to both parties

Either party can cancel (pending/confirmed) or reject (confirmed/in_progress)
    → Payment refunded
    → cancel_reason / reject_reason required
```

## Architecture

Rails API with two namespaces:
- `/api` — authenticated client/provider endpoints
- `/admin` — read-only dashboard

State machine on `Request` (via AASM): `pending → confirmed → in_progress → completed`, with `canceled` and `rejected` as terminal failure states. Each state transition has a dedicated service object (`Requests::CreateService`, `ConfirmService`, `StartService`, etc.).
