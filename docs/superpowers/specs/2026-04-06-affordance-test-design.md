# Affordance Test: Order vs Request Naming Experiment

## Purpose

Explore how entity naming affects AI agent reasoning by creating two identical Rails apps that differ only in the name of the central entity: **Order** (clean, properly refactored) vs **Request** (legacy, invitation-era baggage from a babysitting marketplace called Kidsout).

## Domain

Generic service marketplace. A **Client** books a **Provider** for a service. The booking goes through a lifecycle of state transitions, payments are held and charged, notifications are sent, and reviews are left.

---

## Models

### Client
| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| email | string | unique, required |
| name | string | required |
| phone | string | |
| api_token | string | unique, generated on create |
| notification_preferences | jsonb | default: `{"push":true,"sms":true,"email":true}` |
| timestamps | | |

- has_many :orders / :requests
- has_many :cards
- has_many :reviews (as polymorphic author)

### Provider
| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| email | string | unique, required |
| name | string | required |
| phone | string | |
| api_token | string | unique, generated on create |
| rating | decimal(3,2) | default: 0.0 |
| specialization | string | |
| active | boolean | default: true |
| notification_preferences | jsonb | default: `{"push":true,"sms":true,"email":true}` |
| timestamps | | |

- has_many :orders / :requests
- has_many :reviews (as polymorphic author)

### Order (affordance_order) / Request (affordance_request)
| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| client_id | integer | FK, required |
| provider_id | integer | FK, required |
| scheduled_at | datetime | required |
| duration_minutes | integer | required |
| location | string | |
| notes | text | |
| state | string | required, see state machines below |
| amount_cents | integer | required |
| currency | string | default: "RUB" |
| cancel_reason | text | |
| reject_reason | text | |
| started_at | datetime | |
| completed_at | datetime | |
| timestamps | | |

- belongs_to :client
- belongs_to :provider
- has_one :payment
- has_one :review

### Card
| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| client_id | integer | FK, required |
| token | string | required, emulated Stripe token |
| last_four | string | required |
| brand | string | required (visa, mastercard, etc.) |
| exp_month | integer | required |
| exp_year | integer | required |
| default | boolean | default: false |
| timestamps | | |

- belongs_to :client

### Payment
| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| order_id/request_id | integer | FK, required |
| card_id | integer | FK, nullable (assigned at hold time) |
| amount_cents | integer | required |
| currency | string | default: "RUB" |
| fee_cents | integer | default: 0 |
| status | string | pending/held/charged/refunded |
| held_at | datetime | |
| charged_at | datetime | |
| refunded_at | datetime | |
| timestamps | | |

- belongs_to :order / :request
- belongs_to :card (optional)

### Review
| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| order_id/request_id | integer | FK, required |
| author_type | string | "Client" or "Provider" |
| author_id | integer | FK |
| rating | integer | 1-5, required |
| body | text | |
| timestamps | | |

- belongs_to :order / :request
- belongs_to :author, polymorphic: true
- unique constraint: one review per order/request per author

---

## State Machines

### Order (clean, refactored)

```
pending ──────► confirmed ──────► in_progress ──────► completed
  │                │                   │
  │                │                   │
  ▼                ▼                   ▼
canceled        canceled            rejected
               rejected
```

States: `pending`, `confirmed`, `in_progress`, `completed`, `canceled`, `rejected`

Transitions:
- **confirm**: pending → confirmed (provider action)
- **start**: confirmed → in_progress (provider action)
- **complete**: in_progress → completed (provider action)
- **cancel**: pending|confirmed → canceled (client action, requires reason)
- **reject**: confirmed|in_progress → rejected (provider action, requires reason)

### Request (legacy, invitation-era)

```
created ──────► accepted ──────► started ──────► fulfilled
  │                │                │
  │                │                │
  ▼                ▼                ▼
declined        canceled          rejected
missed          rejected
canceled

created_accepted ──────► started ──────► fulfilled
       │                    │
       │                    │
       ▼                    ▼
    canceled              rejected
    rejected
```

States: `created`, `created_accepted`, `accepted`, `started`, `fulfilled`, `declined`, `missed`, `canceled`, `rejected`

Transitions:
- **accept**: created → accepted (provider action)
- **decline**: created → declined (provider action)
- **miss**: created → missed (system/timeout)
- **start**: accepted|created_accepted → started (provider action)
- **fulfill**: started → fulfilled (provider action)
- **cancel**: created|accepted|created_accepted → canceled (client action, requires reason)
- **reject**: accepted|created_accepted|started → rejected (provider action, requires reason)

Provider-initiated creation: directly creates in `created_accepted` state.

---

## API Endpoints

All endpoints return JSON. Auth via `Authorization: Bearer <api_token>`.

### Shared endpoints (both apps)

```
POST   /api/clients/register
GET    /api/clients/me

POST   /api/providers/register
GET    /api/providers/me

POST   /api/cards
GET    /api/cards
DELETE /api/cards/:id
PATCH  /api/cards/:id/default

GET    /api/payments
GET    /api/payments/:id
```

### Order app

```
POST   /api/orders                  # client creates (pending)
GET    /api/orders                  # list (scoped by role)
GET    /api/orders/:id
PATCH  /api/orders/:id/confirm      # provider
PATCH  /api/orders/:id/start        # provider
PATCH  /api/orders/:id/complete     # provider
PATCH  /api/orders/:id/cancel       # client
PATCH  /api/orders/:id/reject       # provider

POST   /api/orders/:id/reviews
GET    /api/orders/:id/reviews
```

### Request app

```
POST   /api/requests                # client creates (created)
POST   /api/requests/direct         # provider creates (created_accepted)
GET    /api/requests
GET    /api/requests/:id
PATCH  /api/requests/:id/accept     # provider
PATCH  /api/requests/:id/start      # provider
PATCH  /api/requests/:id/fulfill    # provider
PATCH  /api/requests/:id/cancel     # client
PATCH  /api/requests/:id/decline    # provider
PATCH  /api/requests/:id/reject     # provider

POST   /api/requests/:id/reviews
GET    /api/requests/:id/reviews
```

---

## Services

### Order app
- `Orders::CreateService` — creates order (pending), creates pending payment
- `Orders::ConfirmService` — pending → confirmed, notifies client
- `Orders::StartService` — confirmed → in_progress, notifies client
- `Orders::CompleteService` — in_progress → completed, charges payment, notifies both
- `Orders::CancelService` — cancel with reason, refund if held, notifies provider
- `Orders::RejectService` — reject with reason, refund if held, notifies client

### Request app
- `Requests::CreateService` — creates request (created), creates pending payment
- `Requests::CreateAcceptedService` — provider creates (created_accepted), creates pending payment
- `Requests::AcceptService` — created → accepted, notifies client
- `Requests::StartService` — accepted|created_accepted → started, notifies client
- `Requests::FulfillService` — started → fulfilled, charges payment, notifies both
- `Requests::CancelService` — cancel with reason, refund if held, notifies provider
- `Requests::DeclineService` — created → declined, notifies client
- `Requests::RejectService` — reject with reason, refund if held, notifies client

---

## Payment System

### PaymentGateway (emulated Stripe)
All operations log to `log/payments.log` with structured entries.

- `PaymentGateway.hold(payment)` — assigns default card, sets status to `held`, logs `[PAYMENT] action=hold payment_id=7 amount=350000 card=*4242`
- `PaymentGateway.charge(payment)` — captures held amount, sets status to `charged`, logs
- `PaymentGateway.refund(payment)` — refunds charged/held amount, sets status to `refunded`, logs

### Payment lifecycle
1. Order/Request created → Payment created with status `pending`
2. Day before `scheduled_at` → `PaymentHoldJob` calls `PaymentGateway.hold`
3. Order completed/fulfilled → service calls `PaymentGateway.charge`
4. Order canceled/rejected after hold → service calls `PaymentGateway.refund`

---

## Notifications

### NotificationService
`NotificationService.notify(recipient, event, payload)` dispatches to three channels:

1. **Email** — `OrderMailer`/`RequestMailer`, `:test` delivery method
2. **Push** — writes to `log/notifications.log`: `[PUSH] to=client_5 event=order_confirmed order_id=12`
3. **SMS** — writes to `log/notifications.log`: `[SMS] to=+79001234567 event=order_confirmed`

Each channel checks `recipient.notification_preferences` before sending.

### Events that trigger notifications

| Event | Recipient | Channels |
|-------|-----------|----------|
| order_confirmed / request_accepted | client | all |
| order_started / request_started | client | all |
| order_completed / request_fulfilled | both | all |
| order_canceled / request_canceled | provider | all |
| order_rejected / request_rejected | client | all |
| request_declined (Request app only) | client | all |
| review_reminder | both | email only |

---

## Admin Interface

### Authentication
HTTP Basic Auth. Password from `Rails.application.config.admin_password` (set in environment config).

### Routes (all read-only)

```
GET /admin/dashboard
GET /admin/orders (or /admin/requests)
GET /admin/orders/:id (or /admin/requests/:id)
GET /admin/clients
GET /admin/clients/:id
GET /admin/providers
GET /admin/providers/:id
GET /admin/payments
GET /admin/payments/:id
```

### Dashboard
- Count of orders/requests by state
- Total revenue (sum of charged payments)
- Recent activity (last 10 orders/requests)

### Index pages
- Filter form at top (state, date range, client/provider)
- Paginated table
- Query-param based filtering

### Show pages
- All fields displayed
- Associated records (payment, reviews, state transition history)

### Views
- Minimal ERB templates
- Basic inline CSS (no framework)
- Simple nav: Dashboard | Orders/Requests | Clients | Providers | Payments

---

## Test Suite

### Model specs
- All validations, associations, scopes
- State machine: every valid transition, every invalid transition attempt
- Token generation on create
- Card default logic (only one default per client)
- Review uniqueness constraints

### Service specs
- Happy path for each service
- Invalid state transition errors
- Notification dispatch verification
- Payment side effects (hold/charge/refund)
- Request app: extra specs for CreateAccepted, Decline

### Request specs (API)
- All endpoints: success responses, correct JSON structure
- Auth: missing token, invalid token, wrong role
- Validation errors
- State transition constraints
- Card CRUD
- Review constraints (only after completion, one per author)
- List filtering and pagination

### Mailer specs
- Correct recipient and subject for each event
- Notification preferences respected

### Notification specs
- NotificationService dispatches to correct channels
- Log entries are structured correctly
- Preferences filtering

### Admin controller specs
- 401 without auth, 200 with auth
- All pages render
- Filters work correctly
- Dashboard stats accurate

### Job specs
- PaymentHoldJob: finds correct records, places holds, skips already-held
- ReviewReminderJob: finds correct records, sends reminders, skips reviewed

### Factories
- All models with sensible defaults
- Traits: `:confirmed`, `:in_progress`, `:completed`, `:with_payment`, `:with_review`, `:with_card`
- Request app extra traits: `:created_accepted`, `:accepted`, `:fulfilled`, `:declined`, `:missed`

---

## Tech Stack

- Ruby 3.3.5
- Rails 8.1.3 (API mode + admin HTML section)
- SQLite
- AASM for state machines
- RSpec + FactoryBot
- No frontend framework (admin uses plain ERB)

---

## Key Constraint

The two apps must be structurally identical except for:
1. Entity name: Order vs Request
2. Table name: orders vs requests
3. States: clean 6-state vs legacy 9-state
4. Services: 6 vs 8 (extra CreateAccepted, Decline)
5. API routes: /api/orders vs /api/requests + /api/requests/direct
6. All cascading name references (mailer, jobs, admin paths, logs, tests)

No other differences. Same Client, Provider, Card, Payment, Review models. Same notification system. Same admin structure. Same test patterns.
