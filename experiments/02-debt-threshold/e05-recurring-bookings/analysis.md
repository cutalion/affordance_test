# Analysis: e05-recurring-bookings

> Blind comparison — app identities not revealed to analyzer.

## Analysis: Recurring Weekly Bookings (Apps B, C, D, E)

---

### 1. Language/Framing

**App B** (3 runs): Consistently uses "recurring booking" + "requests" language. Clean, uniform framing: "Each of the 5 requests is independent — the provider can accept/decline each individually."

**App C** (3 runs): Mixed framing. Run 1 uses "recurring group" terminology with UUID semantics. Runs 2-3 shift to "recurring booking" grouping "sessions." Notably describes the feature in terms of "booking requests" — a hedged compound noun.

**App D** (3 runs): Consistently frames as "recurring booking" + "**orders**" — not requests. Run 1: "creates the recurring booking and 5 orders scheduled one week apart." Run 2: "creates 1 recurring booking + 5 orders + 5 payments." D is the only app that reframes the unit of work.

**App E** (3 runs): Run 1 uses "recurring group" with UUID language (like C-Run1). Runs 2-3 shift to "recurring booking" + "requests." Similar inconsistency to C.

**Pattern**: Clean apps (B, D) use consistent language across runs. Debt apps (C, E) show framing instability — the AI seems less sure what to call things when the domain model is muddier.

---

### 2. Architectural Choices

| App | Run 1 | Run 2 | Run 3 | Consistency |
|-----|-------|-------|-------|-------------|
| **B** | RecurringBooking model + requests | RecurringBooking model + requests | RecurringBooking model + requests | **High** |
| **C** | UUID `recurring_group_id` column only | RecurringBooking model (thin) | RecurringBooking model + `total_sessions` + `fully_booked?` | **Low** |
| **D** | RecurringBooking model + orders + cancel! + state | RecurringBooking model + orders + payments | RecurringBooking model + orders + payments | **High** |
| **E** | UUID `recurring_group_id` column only | RecurringBooking model + requests | RecurringBooking model + requests | **Low** |

**Key finding**: Both debt apps (C, E) have a Run 1 that avoids creating a new model entirely, choosing instead a lightweight UUID column. Both clean apps (B, D) create a dedicated model in all runs. The debt apps' Run 1 approach (no new model) is arguably the more pragmatic/hacky solution — fitting the pattern of adding to an already-overloaded entity rather than introducing clean separation.

**Confidence**: High. The 2-for-2 split between clean→model and debt→UUID-first is striking.

---

### 3. Model Placement

| App | Creates what? | Correct? |
|-----|--------------|----------|
| **B** (Request + Order) | 5 Requests | Yes — Requests are the entry point; Orders come after acceptance |
| **C** (Request = god object) | 5 Requests | Yes — Request IS the booking here |
| **D** (Request + Order) | 5 Orders (+ Payments) | Debatable — skips the request/approval step |
| **E** (Request = god object) | 5 Requests | Yes — Request IS the booking |

**App D** is the interesting case. It has a clear Request → accept → Order flow, but the AI bypasses Request entirely and creates Orders directly. This implies the AI interpreted "recurring bookings" as pre-agreed work (no negotiation needed). Run 1 even reuses `Orders::CreateService`. This is a reasonable domain interpretation but means 5 orders appear with no originating request, which is a novel pattern in that codebase.

**App B** has the same Request→Order architecture but creates Requests, preserving the approval workflow. The difference: B's AI assumes each session still needs provider approval; D's AI assumes recurring = pre-committed.

**Confidence**: Medium-high. D's choice is defensible but diverges from the existing flow.

---

### 4. State Reuse vs Invention

**Apps B, C, E**: Pure state reuse. All created entities start in their default states (`pending`). No new states invented on existing models.

**App D Run 1**: Invents `state` field on RecurringBooking with `active`/`canceled` states, a `cancel!` method, and a `canceled_at` timestamp. This is genuine state invention on a new model — not on existing models, but still new lifecycle complexity.

**App D Runs 2-3**: No state field. Orders use existing `pending` state.

**Pattern**: State invention only appears in the most complex clean app (D), and only in one run. All debt apps avoid state invention entirely — possibly because the existing state machines are already complex enough to discourage adding more.

---

### 5. Correctness

**App B**: Minor issue — all runs use `Time.parse(@params[:scheduled_at].to_s)` which could fail on unexpected input types. Functionally correct otherwise.

**App C Run 1**: Most defensive — explicitly catches `ArgumentError`/`TypeError` for time parsing. Good error handling.

**App D Run 1**: **Bug** — uses `Orders::CreateService` inside a transaction and catches failure with `raise ActiveRecord::Rollback`. But `ActiveRecord::Rollback` silently swallows the rollback without re-raising, so the method continues past the transaction block, sends a notification, and returns `{ success: true }` with a rolled-back (unsaved) `recurring_booking`. This is a real logic error.

**App D Runs 2-3**: Correct. Direct `create!` calls inside transaction with proper `RecordInvalid` rescue.

**App E Run 1**: Returns errors as `String[]` rather than `ActiveModel::Errors` — inconsistent with the rest of the API. The controller calls `render_unprocessable(result[:errors])` which expects `.full_messages` elsewhere but here receives raw strings.

**Confidence**: High on the D-Run1 bug. It's a well-known Rails antipattern.

---

### 6. Scope

| App | Scope creep items |
|-----|------------------|
| **B** | None — stays on task across all 3 runs |
| **C** | Design spec docs (Runs 1-3), implementation plan doc (Run 1), `fully_booked?` method (Run 3), `recurring` factory trait (Run 1) |
| **D** | Cancel endpoint + state management (Run 1), Payment creation (Runs 1-3) |
| **E** | `recurring?`, `recurring_siblings`, `by_recurring_group` model methods (Run 1), `render_forbidden` access check (Run 2) |

**App D** adds the most unrequested functionality. Payment creation is arguably in-scope (orders need payments to be valid in that system), but the cancel endpoint in Run 1 was not requested.

**App C** generates the most documentation artifacts — full plan documents and design specs, sometimes hundreds of lines.

**App B** is the most disciplined about scope.

---

### Pairwise Comparisons

**B vs C** (Stage 1 Clean vs Debt): B is architecturally consistent (3/3 same approach). C is inconsistent (3 different architectures). Both correctly target Request. C generates more documentation artifacts. B stays leaner.

**B vs D** (Stage 1 vs Stage 2, both Clean): D targets Orders instead of Requests — different model choice. D is more ambitious (payments, cancel). D has a correctness bug in Run 1. B is simpler and more correct.

**C vs E** (Stage 1 vs Stage 2, both Debt): Nearly identical pattern — both have a Run 1 that uses UUID grouping (no new model), then Runs 2-3 that create a RecurringBooking model. The debt seems to cause the same architectural uncertainty regardless of complexity level.

**D vs E** (Stage 2 Clean vs Debt): D creates Orders; E creates Requests. D is more architecturally consistent (3/3 create RecurringBooking model). E has the UUID divergence in Run 1. D is more feature-rich. Both correctly identify their primary bookable entity.

**Clean (B+D) vs Debt (C+E)**: Clean apps produce consistent architectures across runs (6/6 create a dedicated model). Debt apps produce inconsistent architectures (4/6 create a model, 2/6 use UUID column). Clean apps show more confidence; debt apps show more hedging.

---

### Notable Outliers

1. **C-Run1 and E-Run1** both independently arrive at the UUID-grouping approach (no new model). This is the "add a column to the existing table" instinct — arguably the natural response when the existing model is already doing too much.

2. **D-Run1** is the only run across all apps that adds state management and a cancel endpoint — significantly over-scoping. The clean multi-model architecture seems to invite the AI to build richer features.

3. **D-Run1's bug** with `ActiveRecord::Rollback` is the most serious correctness issue across all 36 runs (12 runs × 3 repetitions shown here). It's caused by trying to compose with an existing service (`Orders::CreateService`) inside a transaction — a complexity that only arises because D has a clean service architecture to reuse.

---

### Bottom Line

**Clean codebases produce architecturally consistent AI responses; debt codebases produce inconsistent ones.** Across all runs, clean apps (B, D) generated the same structural approach 6 out of 6 times (dedicated RecurringBooking model), while debt apps (C, E) diverged in 2 out of 6 runs toward a lightweight UUID-column hack — the kind of shortcut that compounds technical debt. However, correctness was not meaningfully worse in debt apps; the single serious bug (D-Run1's silent rollback) actually appeared in a clean app, caused by the AI trying to reuse an existing service in a way that introduced a subtle transaction-safety error. The debt apps' simpler, more direct code was paradoxically less buggy — suggesting that clean architecture invites ambitious composition that can misfire, while messy code keeps the AI conservative and correct.
