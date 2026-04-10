# Analysis: e04-cancellation-fee

> Blind comparison — app identities not revealed to analyzer.

## Analysis: Cancellation Fee Implementation Across Apps B, C, D, E

---

### 1. Language/Framing

**Pattern:** All runs use identical domain vocabulary — "cancellation fee," "late cancellation," "within 24 hours," "partial refund." The only difference is entity names: B/D say "order," C/E say "request." No run reframes the domain differently based on app complexity.

| App | Entity term | Notable framing |
|-----|------------|-----------------|
| B (Bravo, Stage 1 Clean) | "order" / "booking" | Straightforward |
| C (Charlie, Stage 1 Debt) | "request" / "booking" | C-Run1 introduces `LATE_CANCELLATION_WINDOW` constant |
| D (Delta, Stage 2 Clean) | "order" / "booking" | D-Run1 says "booking" in summary |
| E (Echo, Stage 2 Debt) | "request" / "booking" | E-Run2 notes "the existing `fee_cents` column" |

**Confidence:** HIGH — differences are purely entity-name-driven, not complexity-driven.

---

### 2. Architectural Choices

**Pattern:** Two distinct strategies emerge, split along clean/debt lines:

| Strategy | Description | Where it appears |
|----------|-------------|-----------------|
| **Partial refund** | Refund amount minus fee; payment → refunded | B-R1, C-R2, C-R3, D-R1, D-R3, E-R2, E-R3 |
| **Charge cancellation fee** | Charge fee amount; payment → charged | B-R2, B-R3, C-R1, D-R2, E-R1 |

The split is roughly even, but the more interesting pattern is where the fee column lands (see dimension 3). Across runs, clean apps show more architectural consistency while debt apps show more variation — B and D converge on similar patterns across all 3 runs, while C and E each try a different approach per run.

**Confidence:** HIGH

---

### 3. Model Placement — The Key Finding

**Where does `cancellation_fee_cents` live?**

| App | Run 1 | Run 2 | Run 3 |
|-----|-------|-------|-------|
| **B** (Clean) | **Order** | Payment | **Order** + Payment |
| **C** (Debt) | **Request** | Payment | Payment |
| **D** (Clean) | **Order** | **Order** | **Order** |
| **E** (Debt) | Payment | Reuses existing `fee_cents` | Payment |

**Clean apps (B, D):** Fee placed on the booking entity (Order) in **7 of 9 column placements**. The AI treats Order as the natural home for booking-level business data.

**Debt apps (C, E):** Fee placed on Payment in **5 of 6 runs** (only C-Run1 puts it on Request). The AI systematically avoids adding attributes to the already-overloaded Request model.

E-Run1 also adds `late_cancellation?` to the Request model, but the fee data still goes on Payment. Only C-Run1 fully commits to Request as the fee holder.

**Confidence:** HIGH — the pattern is consistent and the explanation (avoiding god object bloat) is plausible.

---

### 4. State Reuse vs Invention

**Pattern:** No new states are invented anywhere. All runs reuse existing AASM states. The only variation is the terminal payment state after a late cancellation:

- **→ refunded** (with fee noted separately): B-R1, C-R2, C-R3, D-R1, D-R3, E-R2, E-R3
- **→ charged** (fee amount charged): B-R2, B-R3, C-R1, D-R2, E-R1

Neither approach is clearly "more correct" — it's a design choice about whether the payment ends as "refunded with deduction" or "charged for fee." No app-specific pattern here; it varies within apps too.

**Confidence:** MEDIUM — the split is real but doesn't correlate with app complexity.

---

### 5. Correctness

| Issue | Severity | Where |
|-------|----------|-------|
| **Reuses `fee_cents` for cancellation fee** | HIGH | E-Run2 — the existing `fee_cents` column stores platform/processing fees (factory default 35,000). Repurposing it for cancellation fees conflates two concepts. The test `expect(payment.reload.fee_cents).to eq(35_000) # unchanged factory default` confirms the column is already semantically loaded. |
| **Mutates `payment.amount_cents`** | MEDIUM | C-Run1 (`payment.update!(amount_cents: fee)`), D-Run1 (`partial_refund!` reduces amount), D-Run2 (same). Destroys the historical record of the original charge. |
| **Boundary: exactly 24h is NOT late** | LOW | C-Run3 uses `< 24.hours` (strict). All other runs use `<=` making exactly-24h a late cancellation. C-Run3 is internally consistent (test confirms with `freeze_time`), but it's the sole outlier. |
| **No nil guard on `scheduled_at`** | LOW | D-Run1 adds `return 0 unless @order.scheduled_at.present?` — the only run with this defensive check. Others assume `scheduled_at` is always set. |

**Debt apps have more correctness issues:** E-Run2's `fee_cents` reuse is the most serious bug. C-Run1's `amount_cents` mutation is the second most problematic. Clean apps' worst issue (D-Run1/R2 mutating `amount_cents`) is the same category but in Payment, not the booking entity.

**Confidence:** MEDIUM-HIGH

---

### 6. Scope

| Scope behavior | Runs |
|----------------|------|
| **On-task** (fee + payment logic + tests) | B-R2, C-R2, C-R3, D-R2, E-R1, E-R2, E-R3 |
| **API response updated** | B-R1, B-R3, C-R1, D-R1 |
| **Notification enriched** | C-R1, D-R3 |
| **Service result enriched** | E-R2 |
| **Extra model methods** | B-R1 (Order#late_cancellation?, #cancellation_fee), C-R1 (Request#late_cancellation?, #cancellation_fee), E-R1 (Request#late_cancellation?) |

Clean apps (B, D) are slightly more likely to update the API response (4/6 runs vs 1/6 for C/E). This might reflect the AI being more confident about the clean codebase's API surface.

**Confidence:** HIGH — all responses are reasonably scoped.

---

### Pairwise Comparisons

**B vs D (Clean Stage 1 vs Clean Stage 2):** Nearly identical approaches. Both anchor fee on Order, both add PaymentGateway.partial_refund. D-Run1 is slightly more thorough (Payment model method, input validation, nil guard). The additional complexity of Stage 2 (Announcements, Responses) doesn't affect the cancellation fee implementation at all — the AI correctly scopes to the Order pathway.

**C vs E (Debt Stage 1 vs Debt Stage 2):** Both avoid the Request model for fee storage. E is more reluctant to touch Request at all (only 1 model method in 3 runs vs C's Run1 adding two methods + constant). E-Run2 produces the worst correctness issue (reusing `fee_cents`). The additional debt in E (god object) may increase the AI's hesitancy to add to or even fully understand the model.

**B vs C (Same stage, Clean vs Debt):** B places fee on Order (the correct booking entity); C mostly places fee on Payment (avoiding the overloaded Request). B's runs are more architecturally consistent. C shows more variation across runs, suggesting the AI is less certain about where things belong.

**D vs E (Same stage, Clean vs Debt):** Sharpest contrast. D is completely consistent (fee on Order, all 3 runs). E never puts fee on the booking entity. D's implementations are cleaner; E's vary more and include the `fee_cents` reuse bug.

---

### Notable Outliers

1. **E-Run2** — Skips migration entirely by reusing `fee_cents` for a semantically different purpose. The only run to avoid a schema change, and the most clearly buggy.

2. **C-Run1** — The most ambitious restructuring: moves `cancel!` after fee logic, enriches notifications, adds model constant. The only debt-app run that puts the fee on the Request model itself.

3. **C-Run3** — Only run to use strict `<` for the 24h boundary (exactly-24h is NOT late). Also the only run adding a `refund_amount_cents` column alongside the fee.

4. **D-Run1** — Only run adding a `partial_refund!` instance method to the Payment model and input validation on refund amounts. Most defensively coded.

---

### Bottom Line

The AI systematically routes new business data away from overloaded models: in clean apps, `cancellation_fee_cents` lands on Order (the booking entity) in 7/9 placements, while in debt apps it lands on Payment in 5/6 runs — a workaround that avoids the god-object Request but creates a less intuitive data model where booking-level policy (the fee) lives on a financial transaction record. This evasion comes at a cost: debt-app implementations show more architectural variation across runs (the AI is less certain about the "right" design), and produce the experiment's worst correctness issue (E-Run2 silently repurposing an existing `fee_cents` column for an entirely different concept). The clean apps, by contrast, converge quickly and consistently on the natural design, suggesting that well-structured models don't just make code easier to maintain — they make AI-generated additions more reliable and predictable.
