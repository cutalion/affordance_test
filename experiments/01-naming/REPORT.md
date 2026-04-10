# Does Entity Naming Shape AI Agent Reasoning?

## Cross-Experiment Report (Revised)

**Date:** 2026-04-08
**Scope:** 7 experiments, 128 runs across 3 apps (Claude Opus and Sonnet), 2 rounds of independent judge reviews (6 judges total)

---

## Executive Summary

We asked whether the *name* of a central entity ("Order" vs "Request") affects how AI agents reason about a codebase. Our initial two-app experiment suggested yes. But when we added a third control app — "Request" naming with Order's clean structure — the answer changed.

**The revised conclusion: structure, not naming, drives AI behavior.**

A third app (`apps/request_clean/`) was created with "Request" as the entity name but the same clean 6-state machine, 6 services, and identical code structure as the Order app. Across 7 experiments and 42 new runs, this control app behaved like the Order app in every case — never like the legacy Request app. Three independent judges, reviewing raw data without access to our prior conclusions, reached the same verdict unanimously.

The word "Request" vs "Order" has no detectable effect on AI-generated code. What matters is what the AI finds in the codebase: the states in the state machine, the events available, the services that exist, the patterns already established.

---

## The Three Apps

| | **App A: Order** | **App B: Request** | **App C: Request Clean** |
|---|---|---|---|
| Entity name | Order | Request | Request |
| States | 6 clean | 9 legacy | 6 clean (same as A) |
| Services | 6 | 8 | 6 (same as A) |
| Extra endpoint | No | Yes | No |
| Purpose | Baseline | Legacy codebase | **Control: isolates naming from structure** |

App C is the decisive test. It shares App B's name but App A's structure. If naming matters, C should behave like B. If structure matters, C should behave like A.

---

## Results by Experiment

| # | Experiment | App C behaves like | What drives differences | Confidence |
|---|---|---|---|---|
| 01 | Describe System | A (Order) | Structure: legacy states trigger editorial commentary | High |
| 02 | Rebook Feature | A (Order) | Structure: state complexity affects implementation approach | Moderate |
| 03 | Counter-Proposal | A (Order) | Structure: existing `decline` event anchors design | High |
| 04 | Bulk Booking | Indistinguishable | Nothing: specific prompt neutralizes all differences | High |
| 05 | Auto-Assignment | A (Order) | Structure + Model: Opus/Sonnet gap dominates | High |
| 06 | Cancellation Fee | Indistinguishable | Model choice dominates | High |
| 07 | Happy Path | A (Order) | Structure: legacy states trigger scope creep | High |

**App C never behaves like App B in any experiment.**

---

## What the Two-App Experiment Got Wrong

The original two-app experiment (Order vs Request, 86 runs) identified several effects attributed to "naming":

1. **Provider agency framing** (Exp 01): Order runs said "confirms," Request runs said "accepts/declines" — originally attributed to naming. **Revised:** The Request app literally has `accept` and `decline` events in its code. The AI described what it saw, not what the name implied. App C (Request name, no decline event) used "confirms" like App A.

2. **State-gating in rebook** (Exp 02): 4/6 Order runs added `rebookable?`; 0/6 Request runs did — originally the strongest "naming effect." **Revised:** App C also added state-gating at comparable rates to App A. The original 0/6 in Request was likely driven by the complex 9-state machine making eligibility ambiguous, not by the word "Request."

3. **Decline behavior** (Exp 03): Request runs unanimously reused the existing `declined` state — originally framed as "naming providing semantic scaffolding." **Revised:** App C, which has no `declined` state, scattered across designs just like App A. This is structural anchoring (existing events constrain design), not naming.

4. **Gateway method extraction** (Exp 06): Request runs added more PaymentGateway methods — originally attributed to naming. **Revised:** The Request app has more services (8 vs 6), establishing a pattern the AI followed. App C, with 6 services, matched App A's behavior.

---

## What the Three-App Experiment Confirmed

### AI agents read structure, not semantic associations

The word "Request" does not activate "invitation" or "negotiation" mental models in AI agents. When App C uses "Request" with clean states, the AI treats it identically to "Order" with clean states. The AI reads the actual code — state definitions, event names, service patterns — not the connotations of the entity name.

### Existing code is the strongest design constraint

When the codebase has a `decline` event, the AI reuses it (Exp 03). When the codebase has 8 services, the AI creates more services (Exp 05, 06). When the codebase has unusual state names, the AI comments on them (Exp 01, 07). The codebase is a style guide that agents follow with high fidelity.

### Prompt specificity still neutralizes differences

Experiments 04 (bulk booking) and 06 (cancellation fee) showed minimal differences across all three apps. Specific, well-scoped prompts produce equivalent results regardless of naming or structure.

### Model choice remains the strongest variable

Opus vs Sonnet consistently produces larger differences than any app-level effect. Opus implements more edge cases, writes more tests, and adds more validation in every experiment.

---

## Judge Consensus (Round 2: Three-App)

Three independent judges reviewed raw data from all 128 runs without access to our prior conclusions:

| Finding | Judge A | Judge B | Judge C |
|---|---|---|---|
| App C behaves like A, not B | Yes (all 7 experiments) | Yes (all 7 experiments) | Yes (3/7 clearly A; 4/7 indistinguishable) |
| Naming alone has detectable effect | No | No | No |
| Structure drives observed differences | Yes | Yes | Yes |
| Existing events/states constrain design | Yes (Exp 03) | Yes (Exp 03) | Yes (Exp 03) |
| Model > App as variance source | Yes | Yes | Yes |

This contrasts with the first round of judges (2-app only), who debated naming vs structure but couldn't resolve it. The third app resolved it decisively.

---

## Practical Implications (Revised)

1. **Renaming entities won't change AI behavior.** If your entity is called "Request" but has clean states and services, AI agents will treat it the same as if it were called "Order." Don't invest in renaming for AI's sake.

2. **Clean up state machines and service patterns instead.** The structural complexity — extra states, extra events, extra services — is what actually shapes AI output. Removing dead states, consolidating redundant services, and simplifying transitions will have measurable impact.

3. **Existing code is the strongest prompt.** Your codebase's patterns (how many services exist, what events are available, what states are defined) act as a template that AI agents follow. If you want different AI behavior, change the code structure, not the names.

4. **Write specific prompts for critical features.** This finding survived from the original experiment — prompt specificity neutralizes both naming and structural differences.

5. **Choose your model wisely.** Opus vs Sonnet matters more than any codebase characteristic for implementation quality.

---

## Limitations

- **Sample size:** N=3 per model per app. Many per-experiment findings are directional, not statistically significant.
- **Single domain:** All apps are booking systems. Results may differ in other domains.
- **Single AI family:** Only Claude models tested. Other models may weight naming differently.
- **Blind analysis was not truly blind:** Run file headers and code content revealed app identity.
- **The apps are not purely identical minus naming:** App B has genuinely more code, which is both the finding (structure matters) and a limitation (we can't test "same structure, different states" without App C).

---

## Experiment Timeline

1. **Phase 1 (2-app):** Built Order and Request apps. Ran 86 experiments. Initial conclusion: naming shapes AI reasoning.
2. **Phase 1 judges:** Three independent reviewers debated naming vs structure as the cause. Judge 3 identified the confound and recommended a third app.
3. **Phase 2 (3-app):** Built Request Clean app (Request naming + Order's clean structure). Ran 42 additional experiments.
4. **Phase 2 judges:** Three independent reviewers unanimously concluded structure, not naming, drives the effects.

---

## Appendix: Run Inventory

| Experiment | Order (A) | Request (B) | Request Clean (C) | Total |
|---|---|---|---|---|
| 01-describe-system | 8* | 6 | 6 | 20 |
| 02-rebook-feature | 6 | 6 | 6 | 18 |
| 03-propose-different-time | 6 | 6 | 6 | 18 |
| 04-bulk-booking | 6 | 6 | 6 | 18 |
| 05-auto-assignment | 6 | 6 | 6 | 18 |
| 06-cancellation-fee | 6 | 6 | 6 | 18 |
| 07-happy-path | 6 | 6 | 6 | 18 |
| **Total** | **44** | **42** | **42** | **128** |

*Experiment 01 has 2 extra Order-Sonnet runs from a pilot configuration.

---

## Appendix: Judge Reports

### Phase 1 (2-app, naming vs structure debated)
- `judge-1.md` — Pattern finder
- `judge-2.md` — Practical advisor
- `judge-3.md` — Skeptic (recommended the third app)

### Phase 2 (3-app, structure confirmed)
- `judge-a.md` — Raw data reviewer
- `judge-b.md` — Data scientist with metrics tables
- `judge-c.md` — Statistician and methodologist

---

*Report covers 7 experiments, 128 runs across 3 apps, and 6 independent judge reviews across 2 phases.*
