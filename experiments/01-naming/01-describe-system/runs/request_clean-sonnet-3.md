# Experiment: 01-describe-system
# App: request_clean | Model: sonnet | Run: 3

---

This is a **service marketplace / booking platform** — specifically a Rails API that manages on-demand service appointments between clients and providers. The domain appears to be modeled after Kidsout (childcare/tutoring services).

## Main Entities

| Entity | Role |
|--------|------|
| **Client** | Person who books services; has saved payment cards and notification preferences |
| **Provider** | Service professional with a rating, specialization, and active/inactive status |
| **Request** | The core booking — links a client to a provider for a scheduled appointment (time, duration, location, price) |
| **Payment** | Attached to each request; tracks hold/charge/refund lifecycle with a fee (10%) |
| **Card** | Saved payment method belonging to a client |
| **Review** | Post-completion rating (1–5) left by either party on a request |

## Typical Workflow

1. **Create** — Client creates a `Request` for a specific provider (`pending` state); a `Payment` record is simultaneously created
2. **Confirm** — Provider confirms → `confirmed`
3. **Start** — Service begins → `in_progress` (records `started_at`)
4. **Complete** — Service finishes → `completed` (records `completed_at`); payment is charged
5. **Review** — Either party leaves a review post-completion

Alternative paths:
- **Cancel** — Client can cancel from `pending` or `confirmed`
- **Reject** — Provider can reject from `confirmed` or `in_progress`

Both cancellation and rejection require a reason field.

## Technical Shape

- Rails 8.1 JSON API with two namespaces: `api/` (client/provider access via API tokens) and `admin/` (read-only dashboard)
- State machine via AASM on `Request`
- Each state transition has a dedicated service object (`Requests::CreateService`, `ConfirmService`, etc.)
- Notifications sent to the relevant party on state changes
- Background jobs: `PaymentHoldJob`, `ReviewReminderJob`
- Currency defaults to RUB, suggesting a Russian market origin (consistent with Kidsout)
