# Analysis: e04-cancellation-fee

> Blind comparison — app identities not revealed to analyzer.

## Analysis: Cancellation Fee Experiment (Apps B, C, D, E)

**Context**: B=app_bravo (Stage 1 Clean), C=app_charlie (Stage 1 Debt), D=app_delta (Stage 2 Clean), E=app_echo (Stage 2 Debt)

---

### 1. Language/Framing

**Pattern**: All runs use "cancellation fee" and "late cancellation" consistently. The AI mirrors whatever entity name the app uses — "order" for B/D, "request" for C/E. All runs freely interchange "booking" as a domain synonym regardless of app.

**Pairwise**:
- **B vs C**: "order canceled" vs "request canceled" — pure name mirroring, no semantic confusion
- **B vs D**: Identical framing (both use Order)
- **C vs E**: Identical framing (both use Request)
- **D vs E**: "order" vs "request" — no evidence the AI treats either name as more or less appropriate for this feature

**Confidence**: High. 12 runs, zero naming confusion. The entity name has no observable effect on framing quality.

---

### 2. Architectural Choices

**Pattern**: Three distinct strategies emerge across all apps:

| Strategy | Runs | Description |
|----------|------|-------------|
| **New gateway method** (charge_cancellation_fee / partial_refund) | B1, B3, C3, D1, D3, E1, E3 | Adds a new class method to PaymentGateway |
| **Modify payment amount + charge** | B2, C1, C2, D2 | Mutates `payment.amount_cents` to the fee, then charges |
| **Extend existing refund** | E2 only | Adds optional `cancellation_fee_cents:` kwarg to existing `refund` |

**Pairwise**:
- **B vs C**: Both show all three strategies across their runs — no systematic difference
- **D vs E**: D leans toward new methods (3/3 runs); E includes the most minimal approach (Run 2 modifies existing method signature)
- **Clean (B,D) vs Debt (C,E)**: Clean apps slightly favor new gateway methods; debt apps show more variety

**Confidence**: Medium. 3 runs per app isn't enough to claim the architecture drives the strategy choice, but E's minimalism is notable.

---

### 3. Model Placement

**Pattern**: Where `cancellation_fee_cents` is stored and where domain logic lives:

| App | Fee column on | Domain methods on model? |
|-----|--------------|------------------------|
| B Run 1 | Payment | No |
| B Run 2 | Order | Yes (`late_cancellation?`, `cancellation_fee`) |
| B Run 3 | Payment (reuses `fee_cents`) | No |
| C Run 1 | Request | Yes (constants + 2 methods) |
| C Run 2 | Request | No (all in service) |
| C Run 3 | Payment | No |
| D Run 1 | Order | No |
| D Run 2 | Order | Yes (constants + 2 methods) |
| D Run 3 | Order + Payment | No |
| E Run 1 | Request | No |
| E Run 2 | Payment | No |
| E Run 3 | Request + Payment | No |

**Key finding**: C Run 1 adds domain constants and methods directly to the Request model — the already-bloated god object. This follows the existing "Request absorbs everything" pattern. App E, despite being the highest-debt app, avoids adding methods to Request in all 3 runs, keeping logic in the service layer.

**Pairwise**:
- **B vs D**: Both sometimes put methods on Order (B2, D2) — clean entity invites enrichment
- **C vs E**: C adds to Request model (Run 1); E never does — the AI may recognize E's Request is already overloaded
- **Clean vs Debt**: Clean apps are slightly more likely to add model methods (B2, D2 vs C1 only)

**Confidence**: Medium. The C1 result is suggestive but not replicated in C2/C3.

---

### 4. State Reuse vs Invention

**Pattern**: No new AASM states invented in any run. All implementations reuse existing payment state transitions:

- **held → charged**: Used when "charging the fee" (B1, B2, C1, C2, D2)
- **held → refunded**: Used when "partial refund" (B3, C3, D1, D3, E1, E2, E3)

This is a significant split: does a late cancellation result in a "charged" or "refunded" payment? Both are defensible but have different audit semantics.

**Pairwise**: No app-level pattern — the choice varies within apps across runs. **Confidence**: High that no new states are created; low confidence in any app-level pattern for which existing state is chosen.

---

### 5. Correctness

**Bugs found**:

| Issue | Runs | Severity |
|-------|------|----------|
| **Boundary inconsistency** (`<=` vs `<` for 24h) | Most use `<=` (fee at exactly 24h); E1 uses strict `<` | Low — design choice, but inconsistent |
| **Mutating `payment.amount_cents`** | B2, C1, C2, D2, E1 | **Medium** — destroys original amount, audit trail lost |
| **D1: fee not persisted on any record** | D1 only | **Medium** — fee is calculated and logged but `charge_cancellation_fee` doesn't store it on the payment |
| **B3 test expects factory default as "no fee"** | B3 only | Low — test smell, not a code bug |
| **D3 migration uses `column_exists?` guard** | D3 only | Low — defensive but unusual for a fresh migration |

**Pairwise**:
- **B vs C**: Similar bug profile (both mutate amount in some runs)
- **D vs E**: D1 has the unique "fee not persisted" bug; E has no significant bugs
- **Clean vs Debt**: No systematic correctness difference

**Confidence**: High on the identified bugs. The "mutating amount_cents" issue appears in 5/12 runs across all apps — it's an AI-wide tendency, not debt-related.

---

### 6. Scope

| App | Scope Creep Instances |
|-----|----------------------|
| B | Run 2: adds `cancellation_fee_cents` to API response |
| C | Run 1: API response + model constants; Run 2: API response |
| D | **Run 2: API response + creates payment when none exists + adds fee to notification** |
| E | None across all 3 runs |

**Key finding**: App D (Stage 2 Clean) has the most scope creep. D Run 2 creates a brand-new payment when the client has a card but no existing payment — a feature nobody asked for. D Run 2 also modifies the notification payload. App E (Stage 2 Debt, highest complexity) stays strictly on-task in all runs.

**Pairwise**:
- **B vs C**: Similar low-level scope creep (API response additions)
- **D vs E**: Stark contrast — D overbuilds, E stays minimal
- **Clean vs Debt at Stage 2**: Clean architecture appears to *invite* more scope creep

**Confidence**: High. The D2 outlier is significant and the E consistency across 3 runs is notable.

---

### Notable Outliers

1. **D Run 2** — Most ambitious implementation by far: creates payments from scratch, modifies notifications, adds 5+ model methods. The clean, well-structured codebase appears to have emboldened the AI.
2. **E Run 2** — Most minimal implementation across all 12 runs: just adds an optional keyword argument to the existing `refund` method. No new gateway methods, no new model methods. High-debt code produced the most surgical change.
3. **D1 correctness bug** — The only run where the fee is computed but never persisted to the database.

---

### Bottom Line

The most important finding is the **inverse relationship between codebase cleanliness and implementation restraint** at Stage 2 complexity. App D (Stage 2 Clean) produced the most scope creep and one notable correctness bug, while App E (Stage 2 Debt — the god-object app) consistently produced minimal, focused, on-task implementations. This suggests that well-structured code may paradoxically invite the AI to "think bigger" and add unrequested features, while visibly messy code triggers a conservative instinct — the AI treads carefully around fragile structures. At Stage 1 (B vs C), this effect is absent; the divergence only appears when architectural complexity increases. This has practical implications: clean codebases may need more explicit scope constraints in prompts to counteract the AI's tendency to elaborate when the architecture makes elaboration easy.
