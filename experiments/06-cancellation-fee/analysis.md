# Analysis: 06-cancellation-fee

> Blind comparison — App A and App B naming not revealed to analyzer.

## Cross-App Analysis: Experiment 06 — Cancellation Fee

---

### 1. Language/Framing

**Pattern summary:** Language tracks the entity name mechanically (`order` → `order_canceled`, `request` → `request_canceled`) but the *business-domain framing* is identical across all three apps. Every run frames the problem as "late cancellation" vs "early cancellation" with a time check against `scheduled_at`.

**Method naming:**
| Method name | A (Order) | B (Request) | C (Req Clean) |
|---|---|---|---|
| `late_cancellation?` | 6/6 | 4/6 | 5/6 |
| `cancellation_fee_applies?` | 0 | 1/6 (sonnet-3) | 0 |
| `<=` vs `<` boundary | all `<` | all `<` | 5/6 `<`, 1/6 `<=` (sonnet-1) |

**Confidence:** Strong pattern — naming has no meaningful effect on domain framing. One minor outlier: request-sonnet-3 chose `cancellation_fee_applies?` — a more abstract name that avoids "late" entirely.

---

### 2. Architectural Choices

Three distinct payment strategies emerged:

| Strategy | Description | A | B | C | Total |
|---|---|---|---|---|---|
| **Fee + Refund** | Record fee_cents, then refund payment (status → refunded) | 3 | 2 | 2 | 7 |
| **Fee + Charge** | Record fee_cents, then charge payment (status → charged) | 2 | 3 | 4 | 9 |
| **Mutate Amount** | Overwrite `amount_cents` to fee value, then charge | 1 | 1 | 0 | 2 |

The "Fee + Charge" approach was most popular overall (9/18). App C skewed heavily toward it (4/6).

**New PaymentGateway methods introduced:**

| App | Runs adding a new gateway method | Method names used |
|---|---|---|
| A (Order) | 2/6 | `charge_fee`, `partial_refund` |
| B (Request) | 5/6 | `refund_with_fee`, `charge_cancellation_fee` (×4) |
| C (Req Clean) | 5/6 | `partial_refund` (×2), `charge_cancellation_fee` (×3) |

**Confidence:** Weak signal. App A was slightly more likely to reuse existing gateway methods (4/6 either reused `charge`/`refund` or only modified `refund`). Apps B and C almost always introduced a dedicated new method.

**Extracted helper methods in CancelService:**

| Pattern | A | B | C |
|---|---|---|---|
| Inline payment logic | 5/6 | 6/6 | 4/6 |
| Extracted `handle_payment_on_cancel` / `process_payment` | 1/6 (opus-3) | 0/6 | 2/6 (sonnet-2, sonnet-3) |

---

### 3. Complexity

**New migration files created:**

| App | Migrations | What was added |
|---|---|---|
| A (Order) | 2/6 (opus-2, sonnet-2) | `cancellation_fee_cents` on orders or payments |
| B (Request) | 1/6 (sonnet-1) | `cancellation_fee_cents` on payments |
| C (Req Clean) | 1/6 (opus-3) | `cancellation_fee_cents` on payments |

**Files modified (median across runs):**

| App | CancelService | PaymentGateway | Payment model | Controller | Migration | Spec |
|---|---|---|---|---|---|---|
| A | 6/6 | 3/6 | 1/6 | 0/6 | 2/6 | 6/6 |
| B | 6/6 | 5/6 | 1/6 | 1/6 | 1/6 | 6/6 |
| C | 6/6 | 5/6 | 1/6 | 1/6 | 1/6 | 6/6 |

**New test cases added (cancel service spec only):**

| App | Average | Range |
|---|---|---|
| A (Order) | 3.0 | 2–4 |
| B (Request) | 2.3 | 1–3 |
| C (Req Clean) | 2.2 | 2–3 |

App A produced slightly more tests. App B's request-opus-1 was the only run to add PaymentGateway tests (3 extra specs).

**Constants extracted:**
- A: 1/6 (opus-3: `LATE_CANCEL_WINDOW`, `LATE_CANCEL_FEE_PERCENT`)
- B: 0/6
- C: 1/6 (sonnet-3: `LATE_CANCELLATION_WINDOW`, `CANCELLATION_FEE_RATIO`)

**Confidence:** Weak signal. Complexity is remarkably uniform. The feature is simple enough that naming/structure didn't create divergence.

---

### 4. Scope

All 18 runs stayed tightly on task. Minor scope expansions:

| Expansion | A | B | C |
|---|---|---|---|
| Added fee to API JSON response | 0/6 | 1/6 (opus-1) | 1/6 (opus-2) |
| Added `cancellation_fee_cents` to result hash | 2/6 | 0/6 | 1/6 |
| Added factory trait | 0/6 | 1/6 (sonnet-2: `:scheduled_soon`) | 0/6 |
| Handled pending payment edge case | 0/6 | 0/6 | 1/6 (sonnet-3) |
| Modified existing refund logging | 1/6 (sonnet-3) | 0/6 | 0/6 |

**Confidence:** No difference. Scope discipline was uniformly good. The one outlier is request_clean-sonnet-3 which handled the pending→held→charged flow — a genuinely unrequested edge case.

---

### 5. Assumptions

**Key assumption: What happens to the payment on late cancel?**

| Outcome | A | B | C |
|---|---|---|---|
| Payment status → `refunded` (fee recorded separately) | 3/6 | 2/6 | 2/6 |
| Payment status → `charged` (fee retained) | 3/6 | 4/6 | 4/6 |

Apps B and C slightly favored "charge" over "refund." This could be noise given the sample size.

**Fee calculation base:**

| Base | A | B | C |
|---|---|---|---|
| `order/request.amount_cents` | 4/6 | 4/6 | 5/6 |
| `payment.amount_cents` | 2/6 | 2/6 | 1/6 |

No meaningful difference.

**Confidence:** No difference driven by naming. The charge-vs-refund split appears model-driven (see below).

---

### 6. Model Comparison (Opus vs Sonnet)

This is the strongest signal in the data:

**Payment outcome by model:**

| Outcome | Opus (9 runs) | Sonnet (9 runs) |
|---|---|---|
| Status → `refunded` | 5/9 (56%) | 2/9 (22%) |
| Status → `charged` | 3/9 (33%) | 7/9 (78%) |
| Mutate amount_cents | 1/9 | 2/9 |

**Sonnet strongly prefers charging; Opus leans toward refunding with fee recorded.** This holds across all three apps.

**New PaymentGateway method naming by model:**

| Model | `partial_refund` | `charge_cancellation_fee` | `refund_with_fee` | `charge_fee` | None/reuse existing |
|---|---|---|---|---|---|
| Opus | 3 | 2 | 1 | 1 | 2 |
| Sonnet | 0 | 6 | 0 | 0 | 3 |

Sonnet overwhelmingly converged on `charge_cancellation_fee` as the method name (6/9 runs, exclusive to Sonnet when creating a new method). Opus used more varied names.

**Confidence:** Strong pattern. The Opus/Sonnet split on payment semantics (refund vs charge) and method naming is the clearest signal in this experiment.

---

### Pairwise Comparisons

**A vs B (Order vs Request — different name, different structure):**
Most different pair in PaymentGateway usage — A reused existing methods more often (4/6 vs 1/6). Otherwise, CancelService logic was essentially identical. The legacy states in B did not cause any additional complexity in cancel handling (the cancel transition works the same way in both).

**A vs C (Order vs Request Clean — different name, same structure):**
Closest pair architecturally. The only systematic difference is method naming (`order` vs `request` substitution). Test counts were similar. Payment strategy distribution was similar.

**B vs C (Request vs Request Clean — same name, different structure):**
Also very similar. Both favored `charge_cancellation_fee` naming, both had 5/6 runs adding new gateway methods. C had slightly more method extraction (2/6 vs 0/6 `handle_payment_on_cancel`), but this is a weak signal.

**Most similar pair:** A vs C (same clean structure, only naming differs — and naming made no difference).
**Most different pair:** A vs B, but only marginally — the difference is in gateway method creation rate, not in the core logic.

---

### Notable Outliers

- **request_clean-sonnet-3**: Most complex implementation — extracted constants, `handle_payment_on_cancel`, separate `charge_cancellation_fee` private method, and handled the pending payment edge case (hold → charge). Only run to consider a payment that isn't already held.
- **order-opus-3**: Most polished App A run — constants, `process_payment` extraction, memoized `cancellation_fee_cents`, boundary test case at 25 hours.
- **request-opus-1**: Only run to add PaymentGateway specs alongside CancelService specs, and to modify the API controller in App B. Broadest scope of any single run.
- **request_clean-opus-1**: Only run to change a factory default (`fee_cents` from 35_000 to 0) — noticed the factory was unrealistic.

---

### Bottom Line

**Entity naming ("Order" vs "Request") and structural complexity (clean vs legacy states) had no measurable effect on how the AI implemented a cancellation fee.** All 18 runs converged on the same core pattern: a `late_cancellation?` time check in CancelService that branches between fee-charging and full-refund paths. The strongest signal is a **model-level difference**: Opus favored a "record fee, then refund" semantic (56%) while Sonnet strongly favored a "charge the fee instead of refunding" semantic (78%), and Sonnet consistently named its gateway method `charge_cancellation_fee` while Opus used varied names. This experiment was straightforward enough — a clean, well-scoped modification to an existing service — that neither ambiguous naming nor legacy state complexity created meaningful friction or divergence.
