# Analysis: 04-bulk-booking

> Blind comparison — App A and App B naming not revealed to analyzer.

## Analysis: Bulk Booking Feature (Experiment 04)

### 1. Language/Framing

**App A (Order):** All runs use transactional, commercial language — "orders," "bulk create," "sessions." The feature is framed as a straightforward batch creation operation. Notification events: `order_created` or `bulk_order_created`.

**App B (Request):** Identical framing — "requests," "bulk create," "sessions." Notification events: `request_created`, `bulk_request_created`, or `bulk_requests_created`. No run in either app introduced language about "invitations," "approvals," or any request-specific semantics.

**Confidence: No difference.** The prompt is concrete enough ("book 5 sessions") that naming had no observable effect on how the feature was described or conceptualized.

### 2. Architectural Choices

| Dimension | App A (Order) | App B (Request) |
|---|---|---|
| Endpoint path | `/api/orders/bulk` or `/bulk_create` | `/api/requests/bulk` |
| Service name | `Orders::BulkCreateService` (6/6) | `Requests::BulkCreateService` (4/6), `CreateBulkService` (1/6), `BulkCreateService` via controller (1/6) |
| DB migration added | 1/6 (opus-2 added `bulk_id` column) | 0/6 |
| Initial state of created records | `"pending"` (all runs) | `"created"` (all runs) |
| Notification strategy | Mixed: per-order (3/6), single bulk (3/6) | Mixed: per-request (3/6), single bulk (3/6) |

The `bulk_id` grouping column in order-opus-2 is a notable outlier — no Request run added a grouping mechanism. This could suggest the "Order" metaphor slightly encourages thinking about batch identity (order numbers, tracking), but with N=1 it's weak.

**Confidence: No difference** in architecture. Both apps produced nearly identical service structures. The state difference (`pending` vs `created`) is a property of the existing codebase, not a design choice.

### 3. Complexity

| Metric | App A (Order) | App B (Request) |
|---|---|---|
| New files (avg) | 1.5 (service + sometimes spec) | 1.5 |
| Service LOC (avg) | ~63 | ~61 |
| Controller additions (avg) | ~22 lines | ~22 lines |
| Request spec test count (avg) | 6.5 | 6.3 |
| Service spec added | 2/6 (opus-2, opus-3) | 2/6 (sonnet-2, sonnet-3) |
| Total new test count (avg) | ~8.5 | ~8.2 |

**Confidence: No difference.** Complexity is virtually identical across apps.

### 4. Scope

| Feature | App A (Order) | App B (Request) |
|---|---|---|
| Configurable `count` param | 4/6 | 4/6 |
| Configurable `interval_days` param | 3/6 | 4/6 |
| Configurable `recurrence` (weekly/daily/biweekly) | 1/6 (opus-1) | 0/6 |
| `bulk_id` grouping field + migration | 1/6 (opus-2) | 0/6 |
| `by_bulk` scope on model | 1/6 (opus-2) | 0/6 |
| Max count validation | 4/6 | 3/6 |
| Max sessions cap | 5 (all except sonnet-1: no cap) | 5 (most), 10 (opus-2), 20 (sonnet-1) |

The `recurrence` enum and `bulk_id` column are both Order-side outliers, but each appears in only one run. Request-sonnet-1 had the most generous max (20 sessions, clamped silently) and Request-opus-2 allowed up to 10 — slightly more permissive defaults on the Request side, but sample is too small.

**Confidence: Weak signal.** Order-side had marginally more scope creep (2 runs added unrequested features vs 0 on Request), but it's driven by a single model (Opus) and is not statistically meaningful.

### 5. Assumptions

Both apps assumed:
- Client-only endpoint (providers get 403) — **unanimous**
- Weekly = 7 days default — **unanimous**
- Each session gets its own Payment — **unanimous**
- Transaction wraps all creates — **unanimous**
- 10% fee calculation — **unanimous**

**Naming of the first-session param varied:**

| Param name | App A (Order) | App B (Request) |
|---|---|---|
| `scheduled_at` | 4/6 | 5/6 |
| `first_scheduled_at` | 1/6 | 0/6 |
| `first_session_at` | 1/6 | 0/6 |

App A showed slightly more creativity in parameter naming, but `scheduled_at` dominated both.

**Confidence: No difference** in assumptions about system purpose or user intent.

### 6. Model Comparison (Opus vs Sonnet)

| Dimension | Opus (both apps) | Sonnet (both apps) |
|---|---|---|
| Service spec added | 3/6 | 3/6 |
| Configurable count/interval | 5/6 | 3/6 |
| Scope creep features | 2/6 (bulk_id, recurrence enum) | 0/6 |
| Avg service LOC | ~67 | ~58 |
| Validation rigor (explicit count/interval bounds) | 4/6 | 1/6 |
| Claude output verbosity | Higher (detailed param lists, file lists) | Lower (table format, terser) |

Opus consistently produced more parameterized, configurable services with explicit validation. Sonnet tended toward hardcoded defaults (5 sessions, 7 days) with less configurability. This Opus-vs-Sonnet difference is **stronger** than any Order-vs-Request difference.

**Confidence: Strong pattern** for model differences. Opus adds more configurability and validation; Sonnet keeps it simpler.

### Notable Outliers

- **order-opus-2**: Only run to add a database migration (`bulk_id` column), model scope, and include the grouping ID in JSON responses. Significantly more ambitious scope.
- **order-opus-1**: Only run to add a `recurrence` parameter (weekly/daily/biweekly). 
- **request-opus-2**: Only run to set MAX_SESSIONS=10 instead of 5, and used `ActiveModel::Errors.new` for manual error construction.
- **request-sonnet-1**: Most permissive bounds (count clamped 2–20, interval 1–365), used `.clamp()` — an unusual Ruby pattern for this context.

### Raw Tallies

| Metric | App A (Order) avg | App B (Request) avg |
|---|---|---|
| New files | 1.5 | 1.5 |
| Service LOC | 63 | 61 |
| Controller additions (LOC) | 24 | 24 |
| Request spec tests | 6.5 | 6.3 |
| Configurable params beyond minimum | 1.2 | 1.0 |
| DB migrations | 0.17 | 0 |

### Bottom Line

**Entity naming (Order vs Request) had no meaningful effect on how the bulk booking feature was implemented.** Both apps produced structurally identical solutions: a service class wrapping a transaction, a collection route, the same parameter patterns, the same authorization model, and comparable test coverage. The most significant variable was **model choice, not entity naming**: Opus consistently produced more configurable, more thoroughly validated services with occasional scope creep (bulk_id grouping, recurrence enums), while Sonnet delivered leaner, more hardcoded implementations. The prompt's specificity ("book 5 sessions at once with the same provider, weekly recurring") left little room for naming-driven interpretation divergence — both "order" and "request" were treated as semantically neutral containers for the booking.
