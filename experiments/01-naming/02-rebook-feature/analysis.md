# Analysis: 02-rebook-feature

> Blind comparison — App A and App B naming not revealed to analyzer.

## Analysis: Rebook Feature Across Three Apps

### 1. Language/Framing

**App A (Order):** Consistently uses "rebook" as the action and "order" as the entity. Language is clean and direct: "rebook an order," "rebookable orders," "new order based on a previous one." The term "rebook" maps naturally onto "order" — you re-order something.

**App B (Request):** Uses "rebook" but the underlying entity is "request." Descriptions are slightly more awkward: "rebook based on a previous booking," "creates a new booking based on a previous request." Several runs introduce the word "booking" as a synonym/clarifier that doesn't appear in App A or C — notably request-opus-1 ("rebook based on a previous booking"), request-opus-2 ("new booking based on a previous request"), request-sonnet-1 ("original booking"). The domain language drifts between "request" and "booking."

**App C (Request Clean):** Similar to App B in entity naming but slightly cleaner descriptions. Uses "previous request" (opus-1, opus-2) or "original request" more consistently. Less "booking" synonym drift than App B.

**Confidence:** Weak signal. The "booking" synonym appears more in App B (3/6 runs) than App C (0/6) or App A (0/6), suggesting the legacy state complexity may push the AI to reach for clearer domain language.

---

### 2. Architectural Choices

#### Service Layer Design

| Pattern | App A (Order) | App B (Request) | App C (Request Clean) |
|---|---|---|---|
| Dedicated RebookService | 6/6 | 6/6 | 4/6 |
| Delegates to CreateService | 3/6 (opus-1,2,3) | 2/6 (opus-3, sonnet-1) | 4/6 (opus-2, sonnet-1,2,3) |
| Reimplements create logic (manual save + Payment.create!) | 3/6 (sonnet-1,2,3) | 4/6 (opus-1,2, sonnet-2,3) | 2/6 (opus-1, opus-3) |
| No separate service (logic in controller) | 0/6 | 0/6 | 2/6 (sonnet-1, sonnet-3) |

**Key finding:** App A Opus consistently delegates to CreateService (3/3). App B has the *lowest* CreateService reuse rate (2/6), with most runs reimplementing the transaction/payment/notification logic manually. App C Sonnet shows the most controller-inlined implementations (2/3 sonnet runs skip the service entirely).

**Confidence:** Moderate signal. App B's legacy complexity seems to discourage service reuse — the AI may be less confident that CreateService handles the rebook case correctly when the state machine is more complex.

#### State Gating (rebookable? checks)

| Pattern | App A | App B | App C |
|---|---|---|---|
| Added `rebookable?` method or state check in service | 3/6 | 0/6 | 0/6 |
| No state restriction on which orders/requests can be rebooked | 3/6 | 6/6 | 6/6 |

App A Opus runs all added explicit rebookable state checks (completed/canceled/rejected). No App B or App C run added any state restriction. This is the starkest difference in the dataset.

**Confidence:** Strong pattern. The "Order" naming with clean states apparently prompted the AI to reason about which terminal states should allow rebooking. The "Request" naming in both B and C triggered no such reasoning — all runs allow rebooking from any state.

#### Model-level additions

| Addition | App A | App B | App C |
|---|---|---|---|
| `rebookable?` instance method | 2/6 | 0/6 | 0/6 |
| `rebookable` scope | 1/6 | 0/6 | 0/6 |
| `rebook_attributes` helper | 1/6 | 0/6 | 0/6 |

Only App A enriched the model layer. App B and C treated this purely as a controller/service concern.

**Confidence:** Strong pattern for App A vs B/C.

---

### 3. Complexity

#### Lines of diff (approximate, excluding specs)

| Run | App A | App B | App C |
|---|---|---|---|
| opus-1 | ~80 | ~70 | ~65 |
| opus-2 | ~60 | ~65 | ~35 (no service) |
| opus-3 | ~75 | ~55 | ~70 |
| sonnet-1 | ~70 | ~55 | ~55 (no service) |
| sonnet-2 | ~70 | ~70 | ~50 |
| sonnet-3 | ~50 | ~70 | ~50 (no service) |

#### New files created

| Metric | App A | App B | App C |
|---|---|---|---|
| New service file | 6/6 | 6/6 | 4/6 |
| New service spec file | 6/6 | 3/6 | 2/6 |
| **Avg new files** | **2.0** | **1.5** | **1.0** |

App A consistently produced the most new files. App C produced the fewest, with 2 runs having no service at all and only 2 runs including service specs.

**Confidence:** Strong pattern. App A prompted more thorough, layered implementations.

#### Test counts (new specs added)

| Metric | App A | App B | App C |
|---|---|---|---|
| Avg service spec examples | 6.5 | 4.7 | 4.3 |
| Avg request spec examples | 5.2 | 5.0 | 5.0 |
| Runs with no service specs | 0/6 | 3/6 | 4/6 |

**Confidence:** Moderate signal. App A inspired more thorough testing at the service layer.

---

### 4. Scope

#### Scope creep indicators

| Feature | App A | App B | App C |
|---|---|---|---|
| Ownership validation (client must own original) | 6/6 | 6/6 | 5/6 |
| State gating (only terminal states rebookable) | 3/6 | 0/6 | 0/6 |
| Optional field overrides (duration, location) | 5/6 | 5/6 | 4/6 |
| Amount override allowed | 2/6 | 3/6 | 2/6 |
| Currency override allowed | 0/6 | 2/6 | 1/6 |

App A is the only one that added *state-based restrictions* — a meaningful business rule not requested in the prompt. This could be read as either beneficial scope expansion (sensible guard) or scope creep. App B runs were slightly more likely to expose amount/currency overrides.

All runs across all apps stayed reasonably on-task. No run added unrelated features (e.g., no one added a "rebook history" or "rebook count" field).

**Confidence:** Moderate. App A's state gating is the only notable scope difference.

---

### 5. Assumptions

**App A** assumed that only *finished* bookings should be rebookable — completed, canceled, or rejected. This reflects a real-world assumption that you wouldn't rebook something still in progress.

**App B** made no such assumption. Every run allows rebooking from any state, including active ones. This may reflect the AI being less certain about the Request lifecycle (with its 9 states including `created_accepted` and `missed`), so it avoided making state-based judgments.

**App C** also made no state restriction despite having the same clean states as App A. This suggests the *naming* (Request vs Order) is what drives the state-reasoning behavior, not the state complexity itself.

**All apps** assumed:
- Client-only action (providers cannot rebook) — universal
- `scheduled_at` is required — universal
- Provider/location/duration should be copied — universal (matches prompt)
- Amount/currency should be copied — nearly universal
- Notes should NOT be copied by default — majority pattern

**Confidence:** Strong. The state-gating assumption is clearly driven by naming, not structure.

---

### 6. Model Comparison (Sonnet vs Opus)

#### Opus patterns
- More likely to create a dedicated service (Opus: 17/18 runs, Sonnet: 13/18 counting all apps... actually let me recount)

Per app:

**App A:** Opus all 3 used CreateService delegation; Sonnet 1/3 used CreateService (sonnet-3), while sonnet-1 and sonnet-2 reimplemented the create logic manually.

**App B:** Opus 1/3 used CreateService (opus-3); Sonnet 1/3 (sonnet-1). So similar.

**App C:** Opus 1/3 used CreateService directly in controller (opus-2); Sonnet 2/3 had no service file at all (sonnet-1, sonnet-3).

| Pattern | Opus (all apps) | Sonnet (all apps) |
|---|---|---|
| Always creates a service file | 9/9 | 6/9 |
| Always creates service specs | 7/9 | 2/9 |
| Delegates to CreateService | 5/9 | 4/9 |
| Adds state gating | 3/9 (all App A) | 0/9 |

**Confidence:** Moderate signal. Opus is more architecturally thorough (always creates service + specs). Sonnet is more pragmatic, sometimes inlining logic into the controller. The state-gating behavior is exclusively Opus + App A.

---

### Pairwise Comparisons

**A vs B (Order vs Request-legacy):** Most different pair. App A adds state gating (3/6), model-level methods (2/6), and more service specs. App B never adds state restrictions and has more manual reimplementation of create logic. The naming difference ("Order" vs "Request") combined with structural complexity produces clearly different architectural choices.

**A vs C (Order vs Request-clean):** Second most different. Despite having identical state machines, App C never adds state gating, produces fewer files, and Sonnet runs skip the service layer entirely. This isolates the *naming* effect: "Order" prompts richer domain modeling than "Request" even with identical structure.

**B vs C (Request-legacy vs Request-clean):** Most similar pair. Neither adds state gating. Both use similar service patterns. The main difference: App B has slightly more manual reimplementation (4/6 vs 2/6), possibly because the legacy state machine makes the AI less confident about reusing CreateService. App C Sonnet is more likely to skip the service layer entirely (2/3 vs 0/3), suggesting the clean structure makes the feature feel "simple enough" to inline.

---

### Notable Outliers

- **order-opus-3** added both `rebookable?` and `rebook_attributes` to the model, plus model specs for all 6 states — the most thorough single run across all apps.
- **request_clean-opus-2** skipped creating a RebookService entirely, putting the rebook logic (field merging) into `rebook_params` in the controller and calling CreateService directly — the most minimal Opus implementation.
- **request_clean-sonnet-3** also inlined everything into the controller with no service, and was the only run to explicitly copy `notes` from the original by default (most runs clear notes).
- **order-sonnet-1** was the only run to allow overriding `amount_cents` via the rebook endpoint in App A.

---

### Raw Tallies Summary

| Metric | App A (Order) | App B (Request) | App C (Request Clean) |
|---|---|---|---|
| Avg new files (impl + spec) | 2.0 | 1.5 | 1.0 |
| State gating added | 3/6 (50%) | 0/6 (0%) | 0/6 (0%) |
| Model enrichment | 2/6 (33%) | 0/6 (0%) | 0/6 (0%) |
| Delegates to CreateService | 3/6 (50%) | 2/6 (33%) | 4/6 (67%) |
| Manual create reimplementation | 3/6 (50%) | 4/6 (67%) | 2/6 (33%) |
| No service file at all | 0/6 (0%) | 0/6 (0%) | 2/6 (33%) |
| Service specs written | 6/6 (100%) | 3/6 (50%) | 2/6 (33%) |

---

### Bottom Line

The clearest finding is that **entity naming drives domain reasoning more than structural complexity does**. "Order" prompted the AI to add state-based rebooking restrictions and model-level abstractions in half its runs; "Request" — even with the identical clean state machine (App C) — never triggered this behavior. The AI treats "Order" as a domain object with lifecycle semantics worth modeling, while "Request" is treated as a more transient, pass-through entity. Separately, the legacy state complexity in App B (9 states) appears to *discourage* service reuse: the AI more often reimplements create logic manually rather than delegating to CreateService, as if uncertain the existing service handles the complexity correctly. App C (Request + clean states) produced the leanest implementations overall, with Sonnet frequently skipping the service layer entirely — suggesting that a simple structure combined with a "lightweight" entity name produces the most minimal AI output.
