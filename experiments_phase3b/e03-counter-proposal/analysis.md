# Analysis: e03-counter-proposal

> Blind comparison — app identities not revealed to analyzer.

# Cross-App Analysis: Counter-Proposal Feature (Apps B, C, D, E)

## Apps Under Analysis

| App | Identity | Architecture |
|-----|----------|-------------|
| B | app_bravo | Stage 1 Clean: Request + Order (two models) |
| C | app_charlie | Stage 1 Debt: Request absorbs booking lifecycle (one god-ish model) |
| D | app_delta | Stage 2 Clean: Request + Order + Announcement + Response |
| E | app_echo | Stage 2 Debt: Request is god object (responses ARE requests) |

**Note:** B Run 2 produced only a design plan with no code. Excluded from code-level analysis (10 implementations total).

---

## 1. Language/Framing

**Pattern:** All apps describe the domain identically — "provider proposes a different time, client accepts or declines." No app's naming or structure caused the AI to frame the feature differently.

**Notable:** B Run 2 was the only run to stop and ask for confirmation before coding. This happened in the cleanest two-model app, suggesting the simpler architecture didn't provide enough "friction" to push the AI into immediate implementation.

**Confidence:** High. Framing is uniform across 12 runs.

---

## 2. Architectural Choices

All runs converge on the same macro-architecture:
- New `counter_proposed` state on Request
- 2 new DB columns (`proposed_scheduled_at` + a text field)
- 3 new service objects
- 3 new PATCH endpoints

**Text field naming diverges by app:**

| App | Column Name | Consistency |
|-----|------------|-------------|
| B | `proposal_reason` | 3/3 runs |
| C | `proposal_note` | 2/3 runs (Run 3: no text column) |
| D | `proposal_reason` | 2/3 runs (Run 2: `proposed_at` timestamp instead) |
| E | `counter_proposal_message` | 3/3 runs |

The debt apps (C, E) show slightly more naming variation. App E consistently chose `counter_proposal_message` — a more "user-facing" name, possibly influenced by the god-object pattern where Request already carries many concerns.

**D Run 2** added an extra `proposed_at` timestamp column tracking when the proposal was made — a scope addition no other run included.

**D Run 3** generated a 756-line implementation plan document — significant scope creep unique to this run.

**Confidence:** High.

---

## 3. Model Placement

**All 10 implementations correctly place counter-proposal on the Request model.** No run attempted to create a separate CounterProposal model or put it on Order/Announcement/Response.

This is the correct choice: counter-proposals happen during the negotiation phase (Request), before any Order exists.

**Confidence:** High. Unanimous across all apps and runs.

---

## 4. State Reuse vs Invention

This is the most divergent dimension. Two key design decisions vary:

### 4a. Accept: Extend existing `accept` event vs. create new event?

| Approach | Runs |
|----------|------|
| Extends existing `accept` (adds `counter_proposed` to `from:`) | B-R1, D-R1, E-R3 |
| Creates new event (`accept_proposal`, `accept_counter`, etc.) | B-R3, C-R1/R2/R3, D-R2/R3, E-R1/R2 |

**New event wins 7-3.** The debt apps (C, E) lean toward new events (5 of 6 runs), while clean apps are split.

### 4b. Decline: Terminal (`declined`) vs. negotiable (back to `pending`)?

| Outcome | Runs |
|---------|------|
| → `declined` (terminal, request is dead) | B-R1, D-R1, D-R2 |
| → `pending` (negotiable, allows re-proposal) | B-R3, **all C**, **all D-R3**, **all E** |

**Key finding: Debt apps (C, E) unanimously chose the negotiable approach (8/8 runs). Clean apps were split (2 terminal, 2 negotiable).**

The negotiable approach is arguably the better design — declining a counter-proposal shouldn't kill the entire booking request. The debt apps' more complex state machines may have paradoxically led to better design: the AI created separate events rather than reusing `decline` (which carries terminal semantics), producing more correct behavior.

### 4c. Cancel from `counter_proposed`

| Extended cancel? | Runs |
|-----------------|------|
| Yes — cancel also works from `counter_proposed` | C-R1/R2/R3, E-R1/R3 |
| No — cancel only from original states | B-R1/R3, D-R1/R2/R3, E-R2 |

Debt apps more consistently extended cancel (5/6 vs 1/6 for clean apps). This makes practical sense — a client should be able to cancel a request regardless of counter-proposal state.

**Confidence:** High. This is the most consistent pattern in the data.

---

## 5. Correctness

### Bug: Dead code after `raise ActiveRecord::Rollback`

```ruby
unless order_result[:success]
  raise ActiveRecord::Rollback
  return error("Failed to create order")  # UNREACHABLE
end
```

After `raise`, the `return` never executes. The transaction rolls back but the method falls through to the success path.

| App | Affected Runs |
|-----|--------------|
| B | R1, R3 |
| C | None (creates Payment directly, no CreateService call) |
| D | R1, R2, R3 |
| E | None (creates Payment directly, no CreateService call) |

**This bug appears exclusively in clean apps (B, D) — 5 of 6 runs.** The debt apps avoid it because they create Payments inline (matching their existing `AcceptService` pattern) rather than delegating to `Orders::CreateService`. The simpler inline pattern turns out to be less error-prone here.

### Terminal decline semantics

B-R1, D-R1, D-R2 transition to `declined` when client declines a counter-proposal. This is a design-level error — it kills the request when the client merely rejected a time change. The debt apps never make this mistake.

### E-R3: Broad event reuse

Extends `accept`, `decline`, `expire`, and `cancel` to all work from `counter_proposed`. This means a provider could theoretically hit the `accept` endpoint on a counter-proposed request (the provider made the proposal — they shouldn't be accepting it). The service layer prevents this, but the model allows it. Minor concern.

**Confidence:** High for the dead-code bug. Medium for the terminal-decline assessment (reasonable people could disagree on the design).

---

## 6. Scope

| Behavior | Runs |
|----------|------|
| Clean implementation (code only) | B-R1/R3, C-R1/R2/R3, D-R1/R2, E-R1/R2/R3 |
| Design-only (no code produced) | B-R2 |
| Extra plan document (756 lines) | D-R3 |

**D-R3** is the outlier — it generated a full implementation plan markdown file, adding ~750 lines of documentation that wasn't requested. This only happened in the Stage 2 Clean app.

All implementations that produced code stayed within the expected scope: migration, model changes, 3 services, controller actions, routes, factory trait, and tests. No run added unrequested features like counter-proposal expiration, multiple rounds tracking, or admin views.

**Confidence:** High.

---

## Pairwise Comparisons

### B vs C (Stage 1 Clean vs Stage 1 Debt)

The clearest contrast. B split between terminal/negotiable decline; C unanimously chose negotiable. B has the dead-code bug in its OrderCreation flow; C avoids it with inline Payment creation. C consistently extended `cancel` from `counter_proposed`; B did not. **C produced more correct implementations despite (or because of) its debt.**

### D vs E (Stage 2 Clean vs Stage 2 Debt)

Same pattern as B vs C, amplified. D has the dead-code bug in all 3 runs; E has it in zero. D-R1 and D-R2 chose terminal decline; E unanimously chose negotiable. D-R3 added an unrequested plan document. **E is more consistent and correct.**

### B vs D (Stage 1 Clean vs Stage 2 Clean)

Very similar behavior. Both have the dead-code bug, both split on terminal vs negotiable decline. D-R2 added a `proposed_at` timestamp (extra scope). D-R3 added the plan document. The additional complexity of D (Announcements, Responses) didn't change behavior much — the AI correctly ignored those models and focused on Request.

### C vs E (Stage 1 Debt vs Stage 2 Debt)

Nearly identical behavior. Both unanimously chose negotiable decline, both create Payments inline, both avoid the dead-code bug. E consistently named its text field `counter_proposal_message` while C used `proposal_note`. E-R3 had the unusual `revert_to_pending` event name and broad event reuse, but overall quality was comparable. **Debt level (Stage 1 vs Stage 2) made almost no difference within the debt category.**

### Clean vs Debt (aggregate)

| Metric | Clean (B+D) | Debt (C+E) |
|--------|------------|------------|
| Terminal decline (design error) | 3/6 runs | 0/8 runs |
| Dead-code bug | 5/6 runs | 0/6 runs |
| Extended cancel from counter_proposed | 1/6 runs | 5/6 runs |
| Non-code output (plan/design only) | 2/6 runs | 0/6 runs |

---

## Notable Outliers

1. **B-R2**: Only run across all 12 that produced no code — stopped at design and asked for confirmation
2. **D-R3**: Only run that generated an implementation plan document (756 lines of unrequested documentation)
3. **E-R3**: Only run to use `revert_to_pending` as an event name and to broadly extend 4 existing events from `counter_proposed`
4. **C-R3**: Only run to omit a text/reason column entirely (only added `proposed_scheduled_at`)

---

## Bottom Line

**The debt apps (C, E) produced more correct and consistent implementations than the clean apps (B, D).** Across all 8 debt-app runs, the AI unanimously chose the better design (negotiable decline back to `pending`), avoided a dead-code bug that afflicted 5 of 6 clean-app runs, and more consistently handled edge cases like cancellation from the new state. The likely mechanism: the debt apps' inline Payment creation pattern is simpler than the clean apps' delegation to `Orders::CreateService`, and the debt apps' richer state machines pushed the AI to create distinct events (with correct semantics) rather than reusing existing ones (with incorrect terminal semantics). This is a counterintuitive result — the "messier" codebases produced cleaner feature additions, suggesting that technical debt's complexity can sometimes function as a form of specification, guiding the AI toward more thorough and correct implementations.
