# Technical Debt Threshold Experiment Design

## Goal

Determine at what level of accumulated technical debt AI agents start making poor design decisions. Instead of surgical lab variants, simulate realistic domain evolution where a codebase outgrows its original model without refactoring.

## Hypothesis

As technical debt accumulates (domain model diverges from business reality), AI agents make increasingly poor design decisions because they follow the misleading structure and vocabulary of existing code. The threshold is expected between stage 1 (single model overload) and stage 2 (god object with three business meanings).

## Prior Findings

The original affordance experiment (128 runs, 3 apps, 7 experiments) established:
- Entity naming alone has no detectable effect on AI behavior
- Codebase structure (states, services, patterns) is the strongest design constraint
- Existing states act as attractors — the AI reuses what it finds
- Model choice (Opus vs Sonnet) matters more than any codebase characteristic

This experiment extends the question: **if structure matters, how much structural debt is required before AI behavior degrades?**

## Domain Evolution

The apps simulate a babysitting/childcare marketplace evolving through three stages:

### Stage 0: MVP — Invitation Model

A client invites a specific provider. Provider accepts or declines. The entity name "Request" fits perfectly — it IS a request/invitation.

### Stage 1: Growth — Order Lifecycle

Business needs payments, cancellation, reviews, stats. The "accepted invitation" must become a trackable booking with lifecycle management.

- **Clean path**: The team refactors. Accepted Request creates an Order. Two models, clear responsibilities.
- **Debt path**: Nobody refactors. Request absorbs payment, cancellation, and review features. `accepted` now means "paid and confirmed" instead of "provider said yes." `AcceptService` captures payment — nothing to do with accepting an invitation.

### Stage 2: Marketplace — Announcements

Client can post job announcements, providers respond, client picks one.

- **Clean path**: Announcement + Response models. Selected Response creates an Order. Three entry paths to Order, each with its own model.
- **Debt path**: Announcement responses ARE Requests. `Announcement has_many :requests`. Selecting a response reuses `AcceptService`. Request now means three different things: invitation, booking, and announcement response.

---

## The Five Apps

### `invitation_mvp` (Stage 0 — shared ancestor)

| Aspect | Details |
|---|---|
| Models | `Request` |
| Request states | `pending`, `accepted`, `declined`, `expired` |
| Request events | `accept`: pending -> accepted, `decline`: pending -> declined, `expire`: pending -> expired |
| Services | `Requests::CreateService`, `Requests::AcceptService`, `Requests::DeclineService` |
| Associations | Request belongs_to :client (User), belongs_to :provider (User). Has scheduled_at, duration_minutes, location, notes |
| API | `POST /api/requests` (create), `PATCH /api/requests/:id/accept`, `PATCH /api/requests/:id/decline` |
| Admin | Standard CRUD + state display |

### `booking_clean` (Stage 1 — Clean)

| Aspect | Details |
|---|---|
| Models | `Request` (unchanged from MVP) + `Order` (new) |
| Request states | `pending`, `accepted`, `declined`, `expired` (unchanged) |
| Order states | `pending`, `confirmed`, `in_progress`, `completed`, `canceled`, `rejected` |
| Order events | `confirm`: pending -> confirmed, `start`: confirmed -> in_progress, `complete`: in_progress -> completed, `cancel`: pending\|confirmed -> canceled, `reject`: confirmed\|in_progress -> rejected |
| Key relationship | `Request has_one :order`. `AcceptService` creates the Order after acceptance. |
| Additional models | `Payment` (belongs_to :order), `Review` (belongs_to :order) |
| Services | Request: same as MVP. Order: `CreateService`, `ConfirmService`, `StartService`, `CompleteService`, `CancelService`, `RejectService` + `PaymentGateway`, `NotificationService` |
| API | Request endpoints (same as MVP) + `POST /api/orders` (direct creation), Order lifecycle endpoints, Payment endpoints |

### `booking_debt` (Stage 1 — Debt)

| Aspect | Details |
|---|---|
| Models | `Request` (bloated) |
| Request states | `pending`, `accepted`, `in_progress`, `completed`, `declined`, `expired`, `canceled`, `rejected` |
| Request events | `accept`: pending -> accepted (NOW captures payment), `decline`: pending -> declined, `expire`: pending -> expired, `start`: accepted -> in_progress, `complete`: in_progress -> completed, `cancel`: pending\|accepted -> canceled, `reject`: accepted\|in_progress -> rejected |
| Additional models | `Payment` (belongs_to :request), `Review` (belongs_to :request) |
| Services | `Requests::CreateService`, `Requests::AcceptService` (captures payment — name lies about responsibility), `Requests::DeclineService`, `Requests::StartService`, `Requests::CompleteService`, `Requests::CancelService`, `Requests::RejectService` + `PaymentGateway`, `NotificationService` |
| API | Same endpoint structure as MVP but extended with lifecycle + payment endpoints |
| Key debt signals | `AcceptService` handles payment capture. `accepted` means "paid and confirmed." Reviews belong to Request. The invitation vocabulary describes transactional events. |

### `marketplace_clean` (Stage 2 — Clean)

| Aspect | Details |
|---|---|
| Models | `Request` + `Order` (from stage 1 clean) + `Announcement` + `Response` (new) |
| Announcement states | `draft`, `published`, `closed` |
| Announcement events | `publish`: draft -> published, `close`: published -> closed |
| Response states | `pending`, `selected`, `rejected` |
| Response events | `select`: pending -> selected (creates Order), `reject`: pending -> rejected |
| Key relationships | `Announcement has_many :responses`. `Response belongs_to :announcement, belongs_to :provider`. Selected Response creates Order via `Orders::CreateService`. |
| Services | Announcement: `Announcements::CreateService`, `Announcements::PublishService`, `Announcements::CloseService`. Response: `Responses::CreateService`, `Responses::SelectService`, `Responses::RejectService` |
| Three paths to Order | (1) Direct creation, (2) Request acceptance, (3) Response selection. Each path has its own model and service. |

### `marketplace_debt` (Stage 2 — Debt / God Object)

| Aspect | Details |
|---|---|
| Models | `Request` (god object) + `Announcement` |
| Request states | `pending`, `accepted`, `in_progress`, `completed`, `declined`, `expired`, `canceled`, `rejected` (same as booking_debt — announcement responses reuse the same states) |
| Announcement states | `draft`, `published`, `closed` |
| Key relationships | `Announcement has_many :requests`. A Request can be created directly (invitation) OR from an announcement response. `Request belongs_to :announcement, optional: true`. |
| Distinguishing field | None. No `source` or `kind` field. The only way to tell if a Request is an invitation or an announcement response is by checking `announcement_id.present?`. Maximum debt — the model itself doesn't know what it represents. |
| Key debt signals | `AcceptService` now serves THREE purposes: (1) provider accepts invitation, (2) payment capture for booking, (3) client selects announcement respondent. Same service, three completely different business operations. No field distinguishes which "kind" of Request this is (or if there is one, the state machine doesn't branch on it). |
| Services | Same as booking_debt + `Announcements::CreateService`, `Announcements::PublishService`, `Announcements::CloseService`. No Response services — responses are just Requests. |

---

## Experiments

### Reused (adapted)

**E01 — Describe System** (readonly)
- Prompt: "Describe what this system does."
- Runs on: all 5 apps
- Measures: How does the AI frame the domain? Does it identify mixed responsibilities in debt apps? Does it notice state names don't match their actual meaning?

**E02 — Happy Path** (readonly)
- Prompt: "What is the happy path for the main entity in this system? Walk through it step by step."
- Runs on: all 5 apps
- Measures: In stage 2 debt (3 flows through same model), which path does the AI pick? Does it get confused or conflate flows?

**E03 — Counter-Proposal** (code)
- Prompt: "Add the ability for providers to propose a different time for a booking. The client can accept or decline the counter-proposal. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation."
- Runs on: stage 1 + stage 2 pairs (4 apps)
- Measures: Model placement (Order vs Request in clean apps). State reuse (does `declined` attract the decline path in debt apps?). Scope creep.

**E04 — Cancellation Fee** (code)
- Prompt: "Add a cancellation fee: if a booking is canceled within 24 hours of the scheduled time, charge the client 50% of the booking amount. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation."
- Runs on: stage 1 + stage 2 pairs (4 apps)
- Measures: In debt apps, can the AI distinguish "cancelable booking" from "declinable invitation"? Does overloaded vocabulary cause incorrect state transitions or bugs?

### New

**E05 — Recurring Bookings** (code)
- Prompt: "Add the ability to create recurring weekly bookings — 5 sessions with the same provider at the same time. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation."
- Runs on: stage 1 + stage 2 pairs (4 apps)
- Measures: In debt apps, what initial state do recurring bookings start in? Does the AI skip invitation states (pending→accepted) or go through them? In clean apps, creates Orders directly.

**E06 — Withdraw Announcement Response** (code)
- Prompt: "Add the ability for a provider to withdraw their response to an announcement before the client makes a decision. Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation."
- Runs on: stage 2 pair only (2 apps)
- Measures: In clean app, straightforward — new state on Response model. In debt app, a response IS a Request. Does the AI add a `withdrawn` state? Reuse `declined`? Reuse `canceled`? Can it distinguish announcement-response-Requests from invitation-Requests?

### Run Matrix

| Experiment | MVP | Stage 1 Clean | Stage 1 Debt | Stage 2 Clean | Stage 2 Debt | Runs |
|---|---|---|---|---|---|---|
| E01 Describe System | 3 | 3 | 3 | 3 | 3 | 15 |
| E02 Happy Path | 3 | 3 | 3 | 3 | 3 | 15 |
| E03 Counter-Proposal | | 3 | 3 | 3 | 3 | 12 |
| E04 Cancellation Fee | | 3 | 3 | 3 | 3 | 12 |
| E05 Recurring Bookings | | 3 | 3 | 3 | 3 | 12 |
| E06 Withdraw Response | | | | 3 | 3 | 6 |
| **Total** | **6** | **15** | **15** | **18** | **18** | **72** |

All runs use Claude Opus only. 3 runs per cell.

---

## Behavioral Markers

### Per-experiment

**E01 — Describe System:**
- Framing: "invitation system" vs "booking platform" vs "marketplace"
- Responsibility identification: does the AI notice `AcceptService` handles payment?
- Vocabulary accuracy: does the AI describe states by their name or their actual function?

**E02 — Happy Path:**
- Flow selection: in stage 2 debt, which of 3 Request flows is "happy"?
- Coherence: does the AI present one clean path or get tangled explaining Request's multiple meanings?
- State description: does the AI note that `accepted` means different things in different contexts?

**E03 — Counter-Proposal:**
- Model placement: feature goes on Order (clean) vs Request (debt)
- Decline path: reuses `declined` (debt) vs invents new state or returns to `pending` (clean)
- Files touched: debt should cause more files touched (mixed responsibilities)

**E04 — Cancellation Fee:**
- Semantic confusion: does the AI apply the fee correctly despite `accepted` meaning "paid"?
- State transition correctness: does the cancel transition work from the right states?
- Bug rate: logical errors caused by overloaded vocabulary

**E05 — Recurring Bookings:**
- Initial state: debt apps — does the AI use `pending` (invitation semantics) or `accepted` (booking semantics)?
- Model placement: creates Orders (clean) vs Requests (debt)
- Flow correctness: does the AI skip invitation states for recurring bookings, or force them through the full invitation flow?

**E06 — Withdraw Response:**
- Clean: new `withdrawn` state on Response (simple, clean)
- Debt: what state/event does the AI use? `declined`? `canceled`? New `withdrawn`?
- Model confusion: can the AI distinguish announcement-response-Requests from invitation-Requests?

### Cross-experiment aggregate markers

1. **Files touched per implementation** — debt apps should spread changes across more files
2. **States invented vs reused** — debt apps should show more reuse of semantically-wrong existing states
3. **Correct model placement** — rate at which AI puts features on the appropriate model
4. **Implementation coherence** — does the implementation work correctly, or does vocabulary overload cause logical errors?
5. **Scope creep** — does the AI add more than requested because the model's mixed responsibilities pull in adjacent concerns?

---

## Analysis Approach

### Blind comparison

Reuse existing `analyze.sh` framework. Apps are labeled App A through E without revealing which is clean vs debt. The analyzer compares implementations looking for structural differences, design quality, and correctness.

### Unblinded summary

After blind analysis, reveal identities and map findings to the debt gradient.

### Independent judges

3 judges review raw runs blind, same methodology as phases 1 and 2. Judge prompt asks: "For each experiment, compare the paired apps. Which produces better design decisions? What specific markers indicate the difference?"

### Predictions (written before running)

| Prediction | Rationale |
|---|---|
| Stage 1 debt shows measurable but small divergence from stage 1 clean | Single model overload — `declined` will attract counter-proposal decline, but cancellation fee will be implemented correctly |
| Stage 2 debt shows large divergence from stage 2 clean | God object with 3 business meanings — AI cannot distinguish which "kind" of Request it's working with |
| E06 (withdraw response) shows the largest clean/debt gap | The task directly requires distinguishing Request types, which is impossible without model boundaries |
| E05 (recurring bookings) reveals initial-state confusion in debt apps | The AI must choose between invitation semantics and booking semantics for new Requests |
| E01/E02 (readonly) show debt apps get less accurate system descriptions | Mixed responsibilities are harder to describe coherently |
| The threshold is between stage 1 and stage 2 | One overloaded model is manageable; a god object serving three flows is where AI behavior breaks down |

---

## Infrastructure

### Directory structure

```
affordance_test/
  invitation_mvp/              # Stage 0 — Rails app
  booking_clean/               # Stage 1 Clean — Rails app
  booking_debt/                # Stage 1 Debt — Rails app
  marketplace_clean/           # Stage 2 Clean — Rails app
  marketplace_debt/            # Stage 2 Debt — Rails app
  experiments_debt/            # New experiment directory
    run.sh                     # Adapted runner (Opus only, 5 apps)
    analyze.sh                 # Adapted analyzer
    e01-describe-system/
      prompt.md
      config.sh                # TYPE=readonly
      runs/
    e02-happy-path/
      prompt.md
      config.sh                # TYPE=readonly
      runs/
    e03-counter-proposal/
      prompt.md
      config.sh                # TYPE=code
      runs/
    e04-cancellation-fee/
      prompt.md
      config.sh                # TYPE=code
      runs/
    e05-recurring-bookings/
      prompt.md
      config.sh                # TYPE=code
      runs/
    e06-withdraw-response/
      prompt.md
      config.sh                # TYPE=code
      runs/
```

### Run configuration

- Model: Opus only
- Runs per cell: 3
- CLAUDE.md: hidden during runs (same as original experiment)
- Code experiments: append "Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation."

### App build order

1. `invitation_mvp` — build from scratch (simplest app)
2. `booking_clean` — extend MVP with Order model
3. `booking_debt` — fork MVP, extend Request instead of adding Order
4. `marketplace_clean` — extend booking_clean with Announcement + Response
5. `marketplace_debt` — extend booking_debt with Announcement, responses as Requests
