# Summary: 04-bulk-booking

**Prompt:** Add a feature where a client can book 5 sessions at once with the same provider (e.g., weekly recurring). All sessions should be created in a single API call. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)

---



## Summary: Experiment 04 — Bulk Booking Feature

### The Setup

Two structurally identical Rails apps were given the same prompt: implement a bulk booking feature ("book 5 sessions at once with the same provider, weekly recurring"). The only difference: **App A** calls its central entity **Order** (with clean states: pending, confirmed, in_progress, completed, canceled, rejected), while **App B** calls it **Request** (with legacy invitation-era states: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected). The Request app evolved from an invitation system but is functionally a booking system — nobody refactored the naming. Each app was tested with 3 Opus and 3 Sonnet runs (6 per app, 12 total).

### Key Finding: Naming Had No Effect

The blind analysis found **no meaningful difference** between the Order and Request apps. Both produced structurally identical solutions: a service class wrapping a transaction, a collection endpoint (`/api/{orders,requests}/bulk`), the same parameter patterns (`scheduled_at`, `count`, `interval_days`), the same authorization model (client-only), and comparable test coverage (~6-7 request spec tests per run). Average service complexity was nearly identical (63 vs 61 LOC). Every assumption — weekly = 7 days, each session gets its own Payment, 10% fee, transactional wrapping — was unanimous across both apps.

This is notable because the Request app's legacy naming and invitation-era states *could* have triggered different reasoning — e.g., treating bulk creation as "sending multiple invitations" rather than "placing a batch order," or introducing approval workflows. None of that happened. The prompt's specificity left no room for naming-driven interpretation divergence.

### The Real Variable: Model Choice

The strongest signal was **Opus vs Sonnet**, not Order vs Request. Opus consistently produced more configurable services with explicit validation (count/interval bounds in 4/6 Opus runs vs 1/6 Sonnet runs) and occasional scope creep — one Opus run added a `bulk_id` database migration for batch grouping, another added a `recurrence` enum (weekly/daily/biweekly). Sonnet delivered leaner, more hardcoded implementations with sensible defaults. This model difference was consistent across both apps.

### Most Interesting Finding

The two scope-creep outliers both came from the **Order** app (Opus runs): a `bulk_id` grouping column and a recurrence enum. While the sample is too small to be conclusive, this hints that the "Order" metaphor may subtly encourage thinking about batch identity and tracking — concepts natural to order processing but less so to request handling. With N=1 for each outlier, this is a weak signal at best, but it's the only place naming *might* have had any influence.

### Confidence

**High confidence** that naming made no difference for this experiment. The prompt was concrete and prescriptive enough that both "Order" and "Request" were treated as semantically neutral containers. This suggests that **specific, well-scoped prompts neutralize naming effects** — a useful finding in itself. The affordance of the name only matters when the AI has room to interpret intent.


## Branches

### Order App

- `experiment/04-bulk-booking/order/opus/run-1`
- `experiment/04-bulk-booking/order/opus/run-2`
- `experiment/04-bulk-booking/order/opus/run-3`
- `experiment/04-bulk-booking/order/sonnet/run-1`
- `experiment/04-bulk-booking/order/sonnet/run-2`
- `experiment/04-bulk-booking/order/sonnet/run-3`

### Request App

- `experiment/04-bulk-booking/request/opus/run-1`
- `experiment/04-bulk-booking/request/opus/run-2`
- `experiment/04-bulk-booking/request/opus/run-3`
- `experiment/04-bulk-booking/request/sonnet/run-1`
- `experiment/04-bulk-booking/request/sonnet/run-2`
- `experiment/04-bulk-booking/request/sonnet/run-3`
