# Analysis: e03-counter-proposal

> Blind comparison — app identities not revealed to analyzer.

## Analysis: Counter-Proposal Feature Across Apps B, C, D, E

### 1. Language/Framing

**Pattern:** Remarkably uniform. All apps across all runs describe this as a "counter-proposal feature for booking requests" with nearly identical summaries. The domain framing doesn't shift based on codebase complexity.

**Minor variation:** App E Run 1 generates a 768-line implementation plan document embedded in the diff — the only run to produce a design artifact alongside the code.

**Confidence: High** — 12 runs, no meaningful divergence in how the domain is described.

---

### 2. Architectural Choices

**Consistent across all:** New `counter_proposed` AASM state on Request, 3 services, 3 API endpoints, migration adding columns.

**Key split — what happens on accept:**
- **Apps B & D (clean):** `AcceptCounterProposalService` delegates to `Orders::CreateService` to create an Order + Payment — correctly mirrors the existing `AcceptService` in those apps.
- **Apps C & E (debt):** `AcceptCounterService` creates `Payment` directly with fee calculation and `PaymentGateway.hold` — correctly mirrors the existing `AcceptService` in those apps where Request absorbs the booking lifecycle.

**Key split — what happens on decline:**
- **B, C, E (9 of 12 runs):** Decline returns to `pending`, clearing proposal fields. Allows re-negotiation.
- **D Runs 2 & 3:** Decline transitions to `declined` (terminal). Reuses the existing `decline` event by expanding `from: [:pending, :counter_proposed]`. This is a fundamentally different UX interpretation — declining a counter-proposal kills the entire request.

**Column choices vary but are reasonable:**

| App | Columns | Notable |
|-----|---------|---------|
| B Run 1 | `proposed_at`, `counter_proposal_reason` | reason optional |
| B Run 2 | `proposed_scheduled_at` | no reason column |
| B Run 3 | `proposed_at`, `proposal_reason` | reason required |
| C Run 1 | `proposed_scheduled_at` | minimal |
| C Run 2 | `proposed_scheduled_at`, `counter_propose_reason` | |
| C Run 3 | `proposed_scheduled_at`, `proposed_duration_minutes`, `proposed_notes` | most expansive |
| D Run 1 | `counter_scheduled_at`, `counter_proposed_at` | timestamp-focused |
| D Run 2 | `proposed_scheduled_at`, `counter_proposed_at` | |
| D Run 3 | `proposed_time`, `counter_proposal_reason` | |
| E Run 1 | `proposed_scheduled_at`, `counter_proposal_message` | |
| E Run 2 | `proposed_scheduled_at`, `counter_proposal_reason` | reason required |
| E Run 3 | `proposed_scheduled_at`, `counter_proposal_message` | adds future-time validation |

**Confidence: High**

---

### 3. Model Placement

**Pattern:** 12/12 runs place the feature on the `Request` model. No run creates a separate `CounterProposal` model. This is correct in all cases — the negotiation happens before an Order exists (B, D) or before acceptance triggers payment (C, E).

**Confidence: High** — unanimous.

---

### 4. State Reuse vs Invention

**Universal:** All runs create a new `counter_proposed` state. All reuse `accepted` as the target state when the client accepts.

**Divergence on decline target:**

| Approach | Runs | Implication |
|----------|------|-------------|
| `counter_proposed` → `pending` (new event) | B×3, C×3, D×1, E Run 1, E Run 3 | Allows re-negotiation |
| `counter_proposed` → `declined` (reuses existing event) | D×2 | Terminal — kills request |
| `counter_proposed` → `pending` (named `revert_to_pending`) | E Run 3 | Same as above but distinct event name |

**Cancel extension:** C (all 3) and E (Runs 1, 3) correctly extend the `cancel` event to allow cancellation from `counter_proposed`. B and D generally don't, which is a minor oversight — a client can't cancel while a counter-proposal is pending.

**Confidence: High**

---

### 5. Correctness

**Shared bug in clean apps (B, D):** All 6 runs of B and D contain an unreachable-code bug in the accept service:

```ruby
Request.transaction do
  # ...
  unless order_result[:success]
    raise ActiveRecord::Rollback    # <-- raises
    return error("Failed to create order")  # <-- UNREACHABLE
  end
end
```

After `raise`, the `return` never executes. If order creation fails, the transaction rolls back but the method falls through to the success notification path. **This is a real bug that would silently succeed when it should fail.**

**Debt apps (C, E) avoid this bug** because they create `Payment` directly rather than delegating to a service that returns a result hash. Their transaction pattern is simpler and correct.

**D Run 2 — fragile validation hack:**
```ruby
validates :decline_reason, presence: true, if: -> { declined? && !counter_proposal_declined? }

def counter_proposal_declined?
  declined? && proposed_scheduled_at.present?
end
```
This infers "was this a counter-proposal decline" from the presence of `proposed_scheduled_at`, which could be stale or misleading. A more robust approach would use the state machine history or a separate flag.

**E Run 3 — adds future-time validation** (`parse_time` + comparison to `Time.current`). This is the only run that validates the proposed time is in the future — a reasonable check others miss, though slightly out of scope.

**Confidence: High** on the raise/return bug (verified across all diffs). Medium on the D Run 2 fragility (edge case).

---

### 6. Scope

| Run | Scope Assessment |
|-----|-----------------|
| B×3 | On task |
| C Run 1-2 | On task |
| C Run 3 | **Over-scope**: adds `proposed_duration_minutes` and `proposed_notes` — prompt says "different time," not "different time, duration, and notes" |
| D Run 1 | On task |
| D Run 2-3 | On task, but terminal decline is a significant design choice |
| E Run 1 | **Over-scope**: generates 768-line plan document in `docs/superpowers/plans/` |
| E Run 2 | On task, requires reason for both propose and decline |
| E Run 3 | Slight over-scope: future-time validation, `revert_to_pending` naming |

The debt apps (C, E) show marginally more scope creep than the clean apps (B, D). C Run 3's addition of duration/notes and E Run 1's plan document are the clearest examples.

---

### Pairwise Comparisons

**B vs C (Stage 1: Clean vs Debt):**
- Both correctly follow their app's existing patterns (Order creation vs direct Payment)
- B inherits the raise/return bug from its Order delegation pattern; C avoids it
- C more consistently extends `cancel` to include `counter_proposed`
- C Run 3 over-scopes with duration/notes

**B vs D (Both clean, different complexity):**
- Nearly identical approach in the simple case
- D shows more architectural variation across runs (Runs 2-3 reuse existing events)
- Both share the same raise/return bug
- D's variation suggests the additional codebase complexity (Announcements, Responses) may introduce design ambiguity

**C vs E (Both debt, different complexity):**
- Very similar core implementations (direct Payment creation, cancel extension)
- E Run 1 produces a plan document (scope creep from complexity?)
- E Run 3 is the most architecturally divergent of any run (revert_to_pending, future validation, expanded existing events)

**D vs E (Stage 2: Clean vs Debt):**
- D delegates to Orders::CreateService, E creates Payment directly — both correct
- D Runs 2-3 make decline terminal; E keeps it returning to pending
- D has the raise/return bug; E doesn't
- Most divergent pair in terms of the decline behavior interpretation

**Clean (B,D) vs Debt (C,E):**
- Clean apps: simpler service code but share a transaction-handling bug
- Debt apps: correctly replicate the more complex payment-handling pattern, bug-free
- Debt apps more consistently handle edge cases (cancel from counter_proposed)
- Debt apps show slightly more scope creep

---

### Notable Outliers

1. **D Run 2** — The only run that modifies existing validation logic (`decline_reason` conditional) and adds a helper method (`counter_proposal_declined?`). Most invasive change to existing code.
2. **E Run 1** — The only run that produces a design document (768 lines). Suggests the AI felt more need to plan before implementing in the complex-debt codebase.
3. **C Run 3** — The only run that proposes changing duration and notes in addition to time. Most expansive feature interpretation.
4. **E Run 3** — The only run that validates proposed time is in the future and uses `revert_to_pending` instead of a decline-specific event. Most defensive implementation.

---

### Bottom Line

The most important finding is that **codebase structure, not naming or complexity level, determined whether the AI produced a bug**. All 6 runs against the clean apps (B, D) contain an identical unreachable-code bug in the accept service's transaction block (`return` after `raise`), while all 6 runs against the debt apps (C, E) avoid it entirely — not because the AI was "smarter" in those codebases, but because the debt apps' pattern of creating Payment directly inside the transaction is structurally simpler than delegating to a sub-service and checking its return value. The AI faithfully replicated each app's existing accept pattern, and the clean apps' pattern happened to have a subtler error-handling requirement that the AI consistently failed to get right. This suggests that the quality of AI-generated code is heavily influenced by the patterns it imitates, and that "cleaner" architecture with more indirection can paradoxically produce buggier AI output when the AI mimics the delegation pattern without fully reasoning through the error paths.
