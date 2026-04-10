# Experiment: 01-describe-system
# App: request_clean | Model: sonnet | Run: 1

---

This is a **service marketplace Rails API** — a booking/scheduling platform where clients hire providers for time-based services.

---

## Domain

Based on the memory context, this is derived from the **Kidsout** domain (a babysitting/childcare marketplace). Clients book providers (e.g., babysitters) for scheduled sessions.

---

## Main Entities

| Entity | Role |
|--------|------|
| **Client** | Consumer who books services; has saved payment cards, notification preferences |
| **Provider** | Service provider with a rating and specialization; can be active/inactive |
| **Request** | A booking — links a client to a provider for a scheduled time slot, with duration and price |
| **Payment** | Financial transaction attached to a Request; tracks holds, charges, and refunds |
| **Card** | Stored payment method belonging to a Client |
| **Review** | Polymorphic — either party (client or provider) can review after a completed Request |

---

## Typical Workflow

A `Request` moves through a state machine:

```
pending → confirmed → in_progress → completed
    ↓           ↓           ↓
 canceled    canceled    rejected
```

1. **Create** — Client creates a Request for a specific provider at a scheduled time
2. **Confirm** — Provider accepts (`pending → confirmed`); a payment hold is placed (`PaymentHoldJob`)
3. **Start** — Session begins (`confirmed → in_progress`); `started_at` is recorded
4. **Complete** — Session ends (`in_progress → completed`); `completed_at` is recorded; payment is charged
5. **Review** — Both parties can leave a rating/review after completion
6. **Cancel** — Client or provider can cancel before it starts (requires `cancel_reason`)
7. **Reject** — Provider can reject mid-session (requires `reject_reason`); likely triggers a refund

Supporting infrastructure: `NotificationService` (push/SMS/email), `PaymentGateway`, `RequestMailer`, and a `ReviewReminderJob` that prompts users to leave reviews.

---

## API Surface

Two namespaces:
- **`/api/`** — Client/provider-facing endpoints (requests, payments, cards, reviews, profiles)
- **`/admin/`** — Internal dashboard for managing clients, providers, requests, payments
