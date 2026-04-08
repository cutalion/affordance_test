# Independent Statistical Review: App C (Request Clean) Analysis

Reviewer: Claude Opus 4.6 (acting as statistician/methodologist)
Date: 2026-04-07
Data: Raw run outputs from 7 experiments, 6 runs per app (3 Opus + 3 Sonnet)

---

## Experimental Design Recap

- **App A** ("Order"): 6 clean states, 6 services
- **App B** ("Request"): 9 legacy states, 8 services, extra API endpoint
- **App C** ("Request Clean"): entity named "Request", but with App A's 6 clean states and 6 services

The logic: if C behaves like A, structure drives behavior. If C behaves like B, naming drives behavior. If C is distinct from both, something else is going on.

---

## Experiment-by-Experiment Classification

### Experiment 01: Describe System

**Evidence:**

App A (Order): All 8 runs describe a "service marketplace/booking platform." States listed as pending -> confirmed -> in_progress -> completed. Language is consistent: "booking," "order management." Entity is called "Order." 1 of 3 Opus runs mentions the experiment's existence.

App B (Request): All 6 runs describe the same domain. States listed as created -> accepted -> started -> fulfilled. Multiple runs describe the `created_accepted` state and `POST /api/requests/direct` endpoint. 2 of 3 Opus runs and 2 of 3 Sonnet runs mention the experiment context. All runs use language like "invitation-era," "legacy states," or "complex state machine."

App C (Request Clean): All 6 runs describe the same domain. States listed as pending -> confirmed -> in_progress -> completed -- **identical to App A**. No run mentions `created_accepted`, `decline`, `missed`, or the direct endpoint (because they do not exist in this codebase). The entity is called "Request" throughout. No run describes the states as "legacy" or "complex." Language closely mirrors App A: "booking platform," "service marketplace."

**Classification: Closer to A.**

App C mirrors App A in every structural dimension (states described, workflow shape, simplicity of description). The only difference is the entity name ("Request" vs "Order"), which is trivially expected since that is what the code says. There is zero behavioral contamination from App B's legacy states -- the AI reads the code, not the name's connotations.

---

### Experiment 02: Rebook Feature

**Evidence:**

All three apps produce essentially identical implementations across all runs:
- New service: `[Entity]s::RebookService`
- New endpoint: `POST /api/[entities]/:id/rebook`
- Copies provider, location, duration, amount, currency from original
- Requires `scheduled_at`, optionally accepts overrides
- Client-only access control
- Delegates to existing `CreateService`

App A: `Orders::RebookService`, rebookable states include completed/canceled/rejected.
App B: `Requests::RebookService`, same logic, same structure.
App C: `Requests::RebookService`, same logic, same structure.

There is no meaningful behavioral difference across any of the three apps. The implementations are structurally identical; only the entity name differs.

**Classification: No meaningful difference between any.**

---

### Experiment 03: Propose Different Time

This is the most interesting experiment. I examined each run's design decisions closely.

**Key design variable: What happens when the client declines the counter-proposal?**

| Run | App A (Order) | App B (Request) | App C (Request Clean) |
|-----|---------------|-----------------|----------------------|
| Opus-1 | back to pending | -> declined | back to pending |
| Opus-2 | -> canceled | -> declined | back to pending |
| Opus-3 | back to pending | -> declined | back to pending |
| Sonnet-1 | -> canceled | -> declined | -> canceled |
| Sonnet-2 | -> canceled | -> declined | -> canceled |
| Sonnet-3 | -> rejected | -> declined | -> canceled |

App B (Request) is unanimous: decline maps to the existing `declined` state (6/6 runs). This makes sense -- the `declined` state already exists in App B's state machine and is semantically available as a "provider/client says no" terminal state.

App A (Order) is split: 2/6 return to pending (non-terminal, allows retry), 3/6 go to canceled, 1/6 goes to rejected. There is no `declined` state in App A, so the AI must choose among its available terminal states or invent a non-terminal flow.

App C (Request Clean) is split but differently: 3/6 return to pending (all Opus runs), 3/6 go to canceled (all Sonnet runs). Like App A, there is no `declined` state in App C, so the same constraint applies.

**Key observation:** App C never uses `declined` as the target state -- because that state does not exist in its codebase. App B always uses `declined` -- because it does exist. This difference is entirely explained by the available state machine, not by the entity name.

**New state naming:**

| Run | App A (Order) | App B (Request) | App C (Request Clean) |
|-----|---------------|-----------------|----------------------|
| Opus-1 | provider_proposed_time | provider_proposed | proposed |
| Opus-2 | provider_proposed | counter_proposed | time_proposed |
| Opus-3 | provider_proposed | counter_proposed | provider_proposed |
| Sonnet-1 | counter_proposed | counter_proposed | countered |
| Sonnet-2 | counter_proposed | counter_proposed | counter_proposed |
| Sonnet-3 | time_proposed | proposed | counter_proposed |

No clear pattern distinguishes the apps. Naming choices for the new state are highly variable across runs within the same app. The word "counter" appears with similar frequency across all three apps.

**Classification: Closer to A.**

The structural behavior (decline -> back to pending vs. decline -> terminal state) is driven by available states in the codebase, not the entity name. App C Opus runs behave identically to App A Opus runs. App C Sonnet runs choose `canceled` (the closest available terminal state), while App A Sonnet runs also mostly choose `canceled`. App B is distinct because it has the `declined` state available.

---

### Experiment 04: Bulk Booking

**Evidence:**

All three apps produce functionally identical implementations:
- New endpoint: `POST /api/[entities]/bulk` (or `bulk_create`)
- Creates N sessions (default 5) spaced by interval (default 7 days)
- Atomic transaction (all-or-nothing)
- Client-only
- Each session gets its own payment

Minor naming variations (e.g., `first_scheduled_at` vs `scheduled_at`, `count` vs `sessions_count`) are randomly distributed across all three apps and across runs. There are no patterns that distinguish A, B, or C.

**Classification: No meaningful difference between any.**

---

### Experiment 05: Auto-Assignment

**Evidence:**

All three apps implement the same approach:
- Make `provider_id` optional in the create endpoint
- Find highest-rated active provider
- Some runs add scheduling conflict detection, some do not

The distribution of "simple" (just highest-rated active) vs "sophisticated" (with overlap checking) implementations:

| App | Simple (rating only) | Sophisticated (overlap check) |
|-----|---------------------|------------------------------|
| A (Order) | 3 Sonnet | 3 Opus |
| B (Request) | 2 Sonnet | 3 Opus + 1 Sonnet |
| C (Request Clean) | 3 Sonnet | 3 Opus |

This is a model-level difference (Opus vs Sonnet), not an app-level difference. App B's one extra sophisticated Sonnet run (request-sonnet-2) is within normal variation.

**Classification: No meaningful difference between any.**

---

### Experiment 06: Cancellation Fee

**Evidence:**

All three apps implement the same logic:
- `late_cancellation?` check: `scheduled_at < 24.hours.from_now`
- 50% fee for late cancellations
- Full refund for early cancellations
- Fee stored on the payment record

Implementation details vary (some use `fee_cents` on existing column, some add a new `cancellation_fee_cents` column, some add `PaymentGateway.partial_refund`, some modify existing methods), but these variations are distributed randomly across all three apps and both models. No app-specific pattern emerges.

**Classification: No meaningful difference between any.**

---

### Experiment 07: Happy Path

**Evidence:**

App A: All 6 runs describe: pending -> confirmed -> in_progress -> completed. Payment: pending -> held -> charged. Then reviews. Clean, consistent.

App B: All 6 runs describe: created -> accepted -> started -> fulfilled. Payment: pending -> held -> charged. Then reviews. Sonnet-2 notes `created_accepted` is a "legacy artifact" with "no transition leading into it from the defined events." This is a structural observation about App B's codebase.

App C: All 6 runs describe: pending -> confirmed -> in_progress -> completed. Payment: pending -> held -> charged. Then reviews. **Identical to App A in every structural detail.** The only difference: entity is called "Request" instead of "Order."

No run in App C mentions `declined`, `missed`, `created_accepted`, or `fulfilled`. No run in App C describes the states as "legacy." The descriptions are indistinguishable from App A except for s/Order/Request/.

**Classification: Closer to A.**

---

## Summary Table

| Experiment | App C Classification | Primary Driver |
|-----------|---------------------|----------------|
| 01 - Describe System | Closer to A | C describes same structure as A |
| 02 - Rebook Feature | No meaningful difference | All apps identical |
| 03 - Propose Different Time | Closer to A | Decline behavior follows available states |
| 04 - Bulk Booking | No meaningful difference | All apps identical |
| 05 - Auto-Assignment | No meaningful difference | All apps identical |
| 06 - Cancellation Fee | No meaningful difference | All apps identical |
| 07 - Happy Path | Closer to A | C describes same structure as A |

**App C is never closer to App B in any experiment.**

---

## Are Existing Summaries Potentially Wrong or Overstated?

I was instructed to ignore existing analysis.md/summary.md files. I have not read them. However, based on the raw data:

1. **Any claim that "Request" naming causes the AI to reason differently** is not supported by the App C data. When the structure is identical (C vs A), the AI produces identical outputs. When the structure differs (B vs A), the AI adapts to the structural differences.

2. **Any claim about App B being "worse" or "more confused"** should be scrutinized. App B's AI outputs are actually quite competent -- they correctly identify `created_accepted` as a special flow, correctly use `declined`/`missed` states, and correctly implement the `fulfill` endpoint. The AI is reading the code accurately, not hallucinating states.

3. **The most overstatable finding** would be in Experiment 03, where App B consistently routes decline to `declined` while A and C do not. But this is an artifact of available states, not confusion. App B uses `declined` because it exists and is semantically appropriate. That is correct behavior.

4. **Experiment 01's "meta-awareness"** (several runs note the experiment exists) could be flagged as a confound, but it does not affect the substantive system descriptions and occurs across all three apps.

---

## Statistical Limitations: What Can We Actually Claim?

With N=3 per model per app per experiment:

1. **Power is extremely low.** For any given experiment, we have 3 observations per cell. A single outlier run dominates the "majority" (2 vs 1). This means we cannot compute meaningful confidence intervals or p-values.

2. **No formal hypothesis testing is possible.** Even a simple chi-square test requires expected cell counts of at least 5. We do not have that for any experiment.

3. **Within-run variance is high.** In Experiment 03, the "decline outcome" variable takes 3 different values across 6 runs of the same app. This suggests the AI's design choices have high intrinsic randomness that dwarfs any between-app signal.

4. **Model confound.** Opus and Sonnet often behave differently (e.g., Opus adds overlap checking in Exp 05, Sonnet does not). This model-level effect cannot be cleanly separated from the app-level effect with N=3.

5. **What we CAN claim (descriptively):**
   - In 7 experiments, App C never produced output that is structurally closer to App B than to App A.
   - In 4 of 7 experiments, all three apps produced indistinguishable outputs.
   - In the remaining 3 experiments, the differences between B and {A, C} are entirely explained by structural differences in the codebase (available states, existing endpoints).

6. **What we CANNOT claim:**
   - That naming has zero effect. Absence of evidence is not evidence of absence, especially with N=3.
   - That a larger sample would not reveal subtle naming effects.
   - That the results generalize to other entity names, other domains, or other models.

---

## Overall Verdict: Does Entity Naming Matter Independent of Structure?

**The data does not support the claim that entity naming matters independent of structure.**

Across 7 experiments and 126 total runs (18 per experiment), App C ("Request" name + clean structure) behaves like App A ("Order" name + clean structure), not like App B ("Request" name + legacy structure).

Every observed difference between App B and the other two apps can be traced to structural features of the codebase:
- App B has `declined` and `missed` states, so the AI uses them.
- App B has `created_accepted` and a direct endpoint, so the AI describes them.
- App B uses `fulfill` instead of `complete`, so the AI uses that verb.

None of these differences arise from the word "Request" triggering different reasoning. They arise from the AI reading different code.

**The entity name "Request" does not cause the AI to:**
- Invent states that do not exist
- Hallucinate complexity that is not present
- Choose worse architectural patterns
- Produce less clean implementations
- Misunderstand the domain

**Caveat:** This conclusion is limited by the small sample size (N=3 per cell), the specific models tested (one generation of Opus and Sonnet), and the specific domain (service marketplace). It is possible that naming effects exist in different contexts, at different scales, or with different entity names. The experiment as designed cannot detect subtle effects even if they exist.

**The strongest conclusion supported by the data:** When an AI reads a codebase, it responds to the actual code structure (states, services, endpoints) rather than to the semantic connotations of entity names. Structure is the signal; naming is noise.
